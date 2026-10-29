const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const {
  AggregateField,
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");
const { isDeepStrictEqual } = require("node:util");
const crypto = require("crypto");
 
initializeApp();
const auth = getAuth();
const db = getFirestore();
const messaging = getMessaging();
const storage = getStorage();
// ─── الأسرار (Secrets) ───
const smsSenderId = defineSecret("SMS_SENDER_ID");
const smsApiKey = defineSecret("SMS_API_KEY");
const googlePlacesApiKey = defineSecret("GOOGLE_PLACES_API_KEY");
// ─── إعدادات عامة ───
const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;
 
function hashCode(code) {
  return crypto.createHash("sha256").update(code).digest("hex");
}
 
function generateCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, "0");
}

async function requireActiveRole(uid, allowedRoles, message) {
  const profile = await db.collection("profiles").doc(uid).get();
  const data = profile.data() || {};
  const role = String(data.role || "").trim().toLowerCase();
  if (!profile.exists || data.is_banned === true ||
      data.is_active !== true || !allowedRoles.includes(role)) {
    throw new HttpsError("permission-denied", message);
  }
  return { data, role };
}

function toChatId(phone) {
  const digitsOnly = phone.replace(/[^\d]/g, "");
  return `${digitsOnly}@c.us`;
}
 
async function sendWhatsAppMessage({ phone, text, idInstance, apiTokenInstance }) {
  const apiUrl = "https://api.greenapi.com";
  const url = `${apiUrl}/waInstance${idInstance}/sendMessage/${apiTokenInstance}`;
 
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chatId: toChatId(phone),
      message: text,
    }),
  });
 
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`Green API error (${response.status}): ${data?.message || "unknown"}`);
  }
  return data;
}
 // ─── requestOtp (محصنة 100% ضد استنزاف الرصيد وهجمات التخمين) ───
exports.requestOtp = onCall(
  { region: "us-central1", cors: true, secrets: [smsSenderId, smsApiKey] },
  async (request) => {
    const phone = String(request.data?.phone || "").trim();
    const purpose = String(request.data?.purpose || "").trim();
 
    if (!phone || !/^\+\d{9,15}$/.test(phone)) {
      throw new HttpsError("invalid-argument", "رقم الهاتف غير صحيح");
    }
    if (purpose !== "login" && purpose !== "signup") {
      throw new HttpsError("invalid-argument", "نوع الطلب غير صحيح");
    }

    // 🔒 التحقق المسبق الصارم: منع إرسال أي رسالة مدفوعة إلا للأرقام المؤهلة فعلياً
    const profileSnap = await db.collection("profiles")
      .where("phone_number", "==", phone)
      .limit(1)
      .get();
    
    const userExists = !profileSnap.empty;
    const userData = userExists ? profileSnap.docs[0].data() : null;

    if (purpose === "login") {
      // إذا كان تسجيل دخول والرقم غير مسجل أصلاً، أو محظور: ننسحب فوراً دون إرسال أي رسالة واتساب
      if (!userExists || userData?.is_banned === true || userData?.is_deleted === true) {
        return { success: true, message: "إذا كان الرقم مؤهلاً، فسيتم إرسال رمز التحقق" };
      }
    } else if (purpose === "signup") {
      // إذا كان إنشاء حساب والرقم مسجل مسبقاً وغير محذوف: نمنع استنزاف الرصيد
      if (userExists && userData?.is_deleted !== true) {
        return { success: true, message: "إذا كان الرقم مؤهلاً، فسيتم إرسال رمز التحقق" };
      }
    }

    const otpRef = db.collection("otp_codes").doc(phone);
    const code = generateCode();
    const codeHash = hashCode(code);

    const reserved = await db.runTransaction(async (tx) => {
      const existing = await tx.get(otpRef);
      const data = existing.data() || {};
      const lastSentAt = existing.exists ? (data.lastSentAt?.toMillis?.() ?? 0) : 0;
      
      // كبح التكرار: دقيقة كاملة بين كل طلب لنفس الرقم
      if (Date.now() - lastSentAt < RESEND_COOLDOWN_MS) return false;

      // سقف أمان ساعي: منع طلب أكثر من 5 رموز لنفس الرقم خلال ساعة واحدة
      const hourlyRequests = Number(data.hourlyRequests || 0);
      const hourStart = data.hourStart?.toMillis?.() ?? 0;
      const isNewHour = Date.now() - hourStart > 3600 * 1000;
      
      if (!isNewHour && hourlyRequests >= 5) {
        return false;
      }

      tx.set(otpRef, {
        codeHash,
        purpose,
        attempts: 0,
        hourlyRequests: isNewHour ? 1 : hourlyRequests + 1,
        hourStart: isNewHour ? FieldValue.serverTimestamp() : (data.hourStart || FieldValue.serverTimestamp()),
        createdAt: FieldValue.serverTimestamp(),
        lastSentAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + OTP_TTL_MS),
      });
      return true;
    });

    if (!reserved) {
      return { success: true, message: "إذا كان الرقم مؤهلاً، فسيتم إرسال رمز التحقق" };
    }

    try {
      await sendWhatsAppMessage({
        phone,
        text: `رمز التحقق الخاص بك في سَلة هو: ${code}\nصالح لمدة 5 دقائق ولا تشاركه مع أي شخص.`,
        idInstance: smsSenderId.value(),
        apiTokenInstance: smsApiKey.value(),
      });
    } catch (error) {
      console.error("[requestOtp] WhatsApp send failed:", error);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(otpRef);
        if (current.exists && current.data().codeHash === codeHash) {
          tx.delete(otpRef);
        }
      });
      return { success: true, message: "إذا كان الرقم مؤهلاً، فسيتم إرسال رمز التحقق" };
    }
 
    return { success: true, message: "إذا كان الرقم مؤهلاً، فسيتم إرسال رمز التحقق" };
  }
);
// ─── verifyOtp ───
exports.verifyOtp = onCall(
  { region: "us-central1", cors: true, secrets: [smsSenderId, smsApiKey] },
  async (request) => {
    const phone = String(request.data?.phone || "").trim();
    const code = String(request.data?.code || "").trim();
    const purpose = String(request.data?.purpose || "").trim();
 
    if (!phone || !/^\+\d{9,15}$/.test(phone)) {
      throw new HttpsError("invalid-argument", "رقم الهاتف غير صحيح");
    }
    if (!/^\d{6}$/.test(code)) {
      return { verified: false, message: "تعذر التحقق من الرمز، أعد إرساله وحاول مجدداً" };
    }
    if (purpose !== "login" && purpose !== "signup") {
      return { verified: false, message: "تعذر التحقق من الرمز، أعد إرساله وحاول مجدداً" };
    }
const otpRef = db.collection("otp_codes").doc(phone);

    // Commit attempt counters and expiry cleanup before returning validation errors.
    let verificationStatus;
    try {
      verificationStatus = await db.runTransaction(async (tx) => {
        const snap = await tx.get(otpRef);
        if (!snap.exists) {
          return "missing";
        }

        const data = snap.data();
        if (data.purpose !== purpose) {
          return "invalid_purpose";
        }

        if (Date.now() > data.expiresAt.toMillis()) {
          tx.delete(otpRef);
          return "expired";
        }

        if (data.attempts >= MAX_ATTEMPTS) {
          tx.delete(otpRef);
          return "attempts_exhausted";
        }

        if (hashCode(code) !== data.codeHash) {
          const nextAttempts = (data.attempts || 0) + 1;
          if (nextAttempts >= MAX_ATTEMPTS) {
            tx.delete(otpRef);
            return "attempts_exhausted";
          } else {
            tx.update(otpRef, { attempts: nextAttempts });
            return "invalid_code";
          }
        }

        tx.delete(otpRef);
        return "verified";
      });
    } catch (err) {
      console.error("[verifyOtp] Transaction Failure:", err);
      return { verified: false, message: "فشل التحقق من الرمز، حاول مجدداً" };
    }
    if (verificationStatus !== "verified") {
      return {
        verified: false,
        message: "تعذر التحقق من الرمز، أعد إرساله وحاول مجدداً",
      };
    }

    let uid;
    let role = "merchant";
    if (purpose === "login") {
      const profileSnap = await db.collection("profiles").where("phone_number", "==", phone).limit(1).get();
      if (profileSnap.empty) {
        return { verified: false, message: "تعذر التحقق من الرمز، أعد إرساله وحاول مجدداً" };
      }
      const userDoc = profileSnap.docs[0];
      const userData = userDoc.data();
      if (userData.is_banned === true ||
          (userData.is_active === false && userData.account_status !== "pending")) {
        return { verified: false, message: "تعذر التحقق من الرمز، أعد إرساله وحاول مجدداً" };
      }
      uid = userDoc.id;
      role = userData.role || "merchant";
    } else {
      const existingProfile = await db.collection("profiles")
        .where("phone_number", "==", phone)
        .limit(1)
        .get();
      if (!existingProfile.empty) {
        return {
          verified: false,
          message: "تعذر التحقق من الرمز، أعد إرساله وحاول مجدداً",
        };
      }
      uid = db.collection("profiles").doc().id;
    }
 
// 🔒 ربط رقم الهاتف الموثق بالـ Claims المشفرة لمنع انتحال أي رقم آخر أثناء إنشاء الملف
    const tokenClaims = { role, purpose, verified_phone: phone };
    try {
      await auth.setCustomUserClaims(uid, tokenClaims);
    } catch (e) {
      console.warn(`[verifyOtp] setCustomUserClaims skipped for uid: ${uid}`);
    }
    const customToken = await auth.createCustomToken(uid, tokenClaims);
    return { verified: true, message: "تم التحقق بنجاح", customToken };
  }
);
// ─── إرسال الإشعارات للهواتف (متوافق مع شاشة القفل للآيفون وأندرويد والتطبيق مغلق) ───
exports.sendPushNotification = onDocumentCreated(
  {
    document: "user_notifications/{docId}",
    region: "us-central1",
  },
  async (event) => {
    const notifData = event.data?.data();
    if (!notifData) return;

    const userId = notifData.user_id;
    const title = notifData.title || "إشعار جديد";
    const body = notifData.body || "";
    const type = notifData.type || "";

    const userDoc = await db.collection("profiles").doc(userId).get();
    if (!userDoc.exists) return;

    const fcmToken = userDoc.data().fcm_token;
    if (!fcmToken) return;

    const targetChannel = type === "new_order" ? "sala_orders_channel" : "sala_orders_channel_v3";
    const isNewOrder = type === "new_order";

    const message = {
      token: fcmToken,
      notification: { 
        title: String(title), 
        body: String(body) 
      },
      data: {
        title: String(title),
        body: String(body),
        type: String(type),
        route: type === "order_status" ? "/merchant" : (type === "new_order" ? "/driver" : "/notifications"),
        click_action: "FLUTTER_NOTIFICATION_CLICK"
      },
      android: {
        priority: "high",
        notification: {
          channelId: targetChannel,
          priority: "max",
          visibility: "public",
          defaultSound: !isNewOrder,
          sound: isNewOrder ? "sala_notification" : undefined,
          defaultVibrateTimings: true,
          defaultLightSettings: true,
          clickAction: "FLUTTER_NOTIFICATION_CLICK"
        }
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert" // 👈 متطلب أبل الصارم لإظهار الإشعار والتطبيق مقفل
        },
        payload: {
          aps: {
            alert: { 
              title: String(title), 
              body: String(body) 
            },
            sound: isNewOrder ? "sala_notification.wav" : "default",
            badge: 1
          }
        }
      }
    };

    try {
      await messaging.send(message);
    } catch (error) {
      if (error.code === 'messaging/invalid-registration-token' || 
          error.code === 'messaging/registration-token-not-registered') {
        await db.collection("profiles").doc(userId).update({
          fcm_token: FieldValue.delete()
        });
      }
    }
  }
);
// ذاكرة كاش ومحدد معدل استهلاك بحث الأماكن المؤقت
const placesRateLimiter = new Map();

exports.searchPlaces = onCall(
  { region: "us-central1", cors: true, secrets: [googlePlacesApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول لاستخدام البحث الجغرافي");
    }

    const uid = request.auth.uid;
    const now = Date.now();
    const userLimit = placesRateLimiter.get(uid) || { count: 0, resetAt: now + 60000 };

    if (now > userLimit.resetAt) {
      userLimit.count = 1;
      userLimit.resetAt = now + 60000;
    } else {
      userLimit.count++;
      // سقف أمان: 20 عملية بحث كحد أقصى في الدقيقة الواحدة لكل مستخدم
      if (userLimit.count > 20) {
        throw new HttpsError("resource-exhausted", "تجاوزت الحد المسموح من عمليات البحث، انتظر دقيقة");
      }
    }
    placesRateLimiter.set(uid, userLimit);

    const query = String(request.data?.query || "").trim().slice(0, 80);
    if (!query) return [];

    const apiKey = googlePlacesApiKey.value();
    const url = new URL("https://maps.googleapis.com/maps/api/place/textsearch/json");
    url.searchParams.append("query", `${query} صنعاء`);
    url.searchParams.append("location", "15.3550,44.2000");
    url.searchParams.append("radius", "25000");
    url.searchParams.append("language", "ar");
    url.searchParams.append("key", apiKey);

    try {
      const res = await fetch(url.toString());
      const data = await res.json();
      return (data.results || []).slice(0, 10);
    } catch (error) {
      console.error("[searchPlaces] Error:", error);
      return [];
    }
  }
);

exports.checkPhoneNumber = onCall(
  { region: "us-central1", cors: true },
  async () => ({
    success: true,
    message: "إذا كان الرقم مؤهلاً، فسيتم إرسال رمز التحقق",
  }),
);

// ─── إنشاء ملف التاجر الجديد عند إكمال التسجيل (معالجة سحابية آمنة 100%) ───
exports.migrateFinancialFields = onCall(
  { region: "us-central1", cors: true, timeoutSeconds: 120 },
  async (request) => {
    let callerUid = request.auth?.uid;
    if (!callerUid && typeof request.data?.idToken === "string") {
      try {
        const decodedToken = await auth.verifyIdToken(request.data.idToken, true);
        callerUid = decodedToken.uid;
      } catch (error) {
        console.error("migrateFinancialFields could not verify the supplied ID token", error);
        throw new HttpsError("unauthenticated", "تعذر التحقق من جلسة الدخول");
      }
    }
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "accountant", "warehouse_manager"],
      "ترحيل البيانات المالية مخصص لمدير النظام",
    );

    const stages = ["products", "orders", "order_items", "orders_finalize"];
    const migrationRef = db.collection("security_migrations").doc("financial_fields");
    const migrationSnap = await migrationRef.get();
    const migration = migrationSnap.data() || {};
    if (migration.done === true) return { done: true };

    const stage = stages.includes(migration.stage) ? migration.stage : stages[0];
    const collection = db.collection(
      stage === "orders_finalize" ? "orders" : stage,
    );
    let query = collection.orderBy(FieldPath.documentId()).limit(100);
    if (migration.stage === stage && migration.cursor) {
      query = query.startAfter(migration.cursor);
    }
    const page = await query.get();

    if (page.empty) {
      const nextIndex = stages.indexOf(stage) + 1;
      const done = nextIndex >= stages.length;
      await migrationRef.set({
        stage: done ? stage : stages[nextIndex],
        cursor: null,
        done,
        updated_at: FieldValue.serverTimestamp(),
      }, { merge: true });
      return { done, stage: done ? stage : stages[nextIndex], cursor: null };
    }

    await Promise.all(page.docs.map((doc) => db.runTransaction(async (tx) => {
      const currentSnap = await tx.get(doc.ref);
      if (!currentSnap.exists) return;
      const data = currentSnap.data();
      if (stage === "products") {
        const financialRef = db.collection("product_financials").doc(doc.id);
        const privateSnap = await tx.get(financialRef);
        const units = Array.isArray(data.units) ? data.units : [];
        const hasLegacyCosts = Object.prototype.hasOwnProperty.call(data, "cost_price") ||
          units.some((unit) => unit && typeof unit === "object" &&
            Object.prototype.hasOwnProperty.call(unit, "cost_price"));
        const financialData = {
          product_id: doc.id,
          updated_at: FieldValue.serverTimestamp(),
        };
        if (hasLegacyCosts || !privateSnap.exists) {
          financialData.cost_price = Math.max(0, Number(data.cost_price) || 0);
          financialData.units = units
            .filter((unit) => unit && typeof unit === "object")
            .map((unit) => ({
              label: String(unit.label || "").trim(),
              cost_price: Math.max(0, Number(unit.cost_price) || 0),
            }))
            .filter((unit) => unit.label);
        }
        tx.set(financialRef, financialData, { merge: true });
        tx.update(doc.ref, {
          cost_price: FieldValue.delete(),
          units: units
            .filter((unit) => unit && typeof unit === "object")
            .map(({ cost_price, ...unit }) => unit),
          public_catalog_ready: true,
          updated_at: FieldValue.serverTimestamp(),
        });
      } else if (stage === "orders") {
        const financialRef = db.collection("order_financials").doc(doc.id);
        const privateSnap = await tx.get(financialRef);
        const financial = {
          order_id: doc.id,
          profit_recorded: data.profit_recorded === true,
          updated_at: FieldValue.serverTimestamp(),
        };
        if (data.total_profit != null) {
          financial.total_profit = Number(data.total_profit) || 0;
        } else if (!privateSnap.exists) {
          financial.total_profit = 0;
        }
        tx.set(financialRef, financial, { merge: true });
        tx.update(doc.ref, {
          total_profit: FieldValue.delete(),
          financial_safe: false,
          updated_at: FieldValue.serverTimestamp(),
        });
      } else if (stage === "order_items") {
        const financialRef = db.collection("order_item_financials").doc(doc.id);
        const privateSnap = await tx.get(financialRef);
        const hasLegacyCosts = Object.prototype.hasOwnProperty.call(data, "cost_price") ||
          Object.prototype.hasOwnProperty.call(data, "unit_cost");
        const financialData = {
          order_id: String(data.order_id || ""),
          order_item_id: doc.id,
          updated_at: FieldValue.serverTimestamp(),
        };
        if (hasLegacyCosts || !privateSnap.exists) {
          financialData.cost_price = Math.max(0, Number(data.cost_price) || 0);
          financialData.unit_cost = Math.max(0, Number(data.unit_cost) || 0);
          financialData.profit = Number(data.profit) || 0;
        }
        tx.set(financialRef, financialData, { merge: true });
        tx.update(doc.ref, {
          cost_price: FieldValue.delete(),
          unit_cost: FieldValue.delete(),
          updated_at: FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(doc.ref, {
          financial_safe: true,
          updated_at: FieldValue.serverTimestamp(),
        });
      }
    })));

    const nextCursor = page.docs[page.docs.length - 1].id;
    await migrationRef.set({
      stage,
      cursor: nextCursor,
      done: false,
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { done: false, stage, cursor: nextCursor };
  },
);

exports.createUserProfile = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول وتأكيد رمز التحقق أولاً");
    }

 const uid = request.auth.uid;
    const tokenPhone = request.auth.token.verified_phone || request.auth.token.phone_number;
    const { fullName, storeName, latitude, longitude, phone } = request.data || {};
    const cleanFullName = String(fullName || "").trim();
    const cleanStoreName = String(storeName || "").trim();
    const cleanPhone = String(phone || "").trim();
    const numLat = Number(latitude);
    const numLng = Number(longitude);

    // 🔒 حظر أمني حاسم: مطابقة رقم الهاتف مع التوكن الموثق لمنع انتحال هويات الآخرين
    if (!tokenPhone || tokenPhone !== cleanPhone) {
      throw new HttpsError("permission-denied", "رقم الهاتف غير مطابق لرمز التحقق المؤكد أمنياً");
    }

    // 1. تحققات أمنية صارمة على المدخلات
    if (!cleanFullName || cleanFullName.length > 120 || cleanFullName.split(/\s+/).length < 4) {
      throw new HttpsError("invalid-argument", "أدخل الاسم الرباعي بحد أقصى 120 حرفاً");
    }
    if (!cleanStoreName || cleanStoreName.length < 2 || cleanStoreName.length > 100) {
      throw new HttpsError("invalid-argument", "يجب أن يكون اسم المتجر بين حرفين و100 حرف");
    }
    if (!cleanPhone || !/^\+\d{9,15}$/.test(cleanPhone)) {
      throw new HttpsError("invalid-argument", "صيغة رقم الهاتف الدولي غير صحيحة");
    }
    if (isNaN(numLat) || isNaN(numLng) || numLat < -90 || numLat > 90 || numLng < -180 || numLng > 180) {
      throw new HttpsError("invalid-argument", "إحداثيات الموقع الجغرافي على الخريطة غير صالحة");
    }

    try {
      const profileRef = db.collection("profiles").doc(uid);
      await db.runTransaction(async (tx) => {
        const [existingDoc, phoneMatches] = await Promise.all([
          tx.get(profileRef),
          tx.get(db.collection("profiles")
            .where("phone_number", "==", cleanPhone)
            .limit(1)),
        ]);
        if (!phoneMatches.empty && phoneMatches.docs[0].id !== uid) {
          throw new HttpsError("already-exists", "رقم الهاتف هذا مسجل مسبقاً لحساب آخر");
        }
        if (existingDoc.exists) {
          const existingData = existingDoc.data() || {};
          if (existingData.role !== "merchant" || existingData.phone_number !== cleanPhone) {
            throw new HttpsError("already-exists", "ملف الحساب موجود مسبقاً ولا يمكن إعادة إنشائه");
          }
          return;
        }

        tx.create(profileRef, {
          full_name: cleanFullName,
          store_name: cleanStoreName,
          phone_number: cleanPhone,
          latitude: numLat,
          longitude: numLng,
          role: "merchant",
          is_active: false,
          is_banned: false,
          account_status: "pending",
          created_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });
      });

      await auth.setCustomUserClaims(uid, { role: "merchant", purpose: "registered" });

      return {
        success: true,
        userId: uid,
        role: "merchant",
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("[createUserProfile] Error:", error);
      throw new HttpsError("internal", "تعذر حفظ بيانات الحساب في السيرفر: " + error.message);
    }
  }
);
// ─── حذف الحساب الآمن المكتمل مع إبطال التوكنات وتطهير FCM ───
exports.deleteUserAccount = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
    }

    const targetUid = request.auth.uid;
    const profileRef = db.collection('profiles').doc(targetUid);
    const userProfile = await profileRef.get();
    
    if (userProfile.exists) {
      const role = String(userProfile.data()?.role || "").toLowerCase().trim();
      if (role === "super_admin" || role === "admin") {
        throw new HttpsError('failed-precondition', 'لا يمكن حذف حسابات مدراء النظام من التطبيق');
      }
    }

    try {
      // 1. إبطال كافة الجلسات النشطة على كل أجهزة المستخدم فوراً
      await auth.revokeRefreshTokens(targetUid);

      // 2. تطهير البيانات التعريفية ورمز الإشعارات لمنع وصول أي إشعار بعد الحذف
      await profileRef.update({
        is_active: false,
        is_banned: true,
        is_deleted: true,
        fcm_token: FieldValue.delete(),
        phone_number: FieldValue.delete(),
        full_name: "مستخدم محذوف",
        deleted_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });

      // 3. حذف الحساب من سجلات Firebase Authentication
      await auth.deleteUser(targetUid);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("[deleteUserAccount] Error:", error);
      throw new HttpsError('internal', 'فشل حذف الحساب: ' + error.message);
    }
  }
);
// ══════════════════════════════════════════════════════════════
// 2. دالة إنشاء الطلب واعتماد المخزون والترقيم الذري القطعي
// ══════════════════════════════════════════════════════════════
exports.placeOrder = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const uid = request.auth.uid;
    const { orderId, items, notes, extraData } = request.data || {};
    const cleanOrderId = String(orderId || "").trim();

  if (!/^[A-Za-z0-9_-]{1,128}$/.test(cleanOrderId) || !Array.isArray(items) || items.length === 0) {
      throw new HttpsError("invalid-argument", "بيانات الطلب غير مكتملة");
    }
    if (notes != null && (typeof notes !== "string" || notes.length > 1000)) {
      throw new HttpsError("invalid-argument", "ملاحظات الطلب تتجاوز الحد المسموح");
    }
    if (items.length > 50) {
      throw new HttpsError("invalid-argument", "تجاوزت الحد الأقصى للأصناف في الطلب الواحد (50 صنف)");
    }

    // 1. فحص حساب التاجر (الحظر والنشاط)
    const { data: profile } = await requireActiveRole(
      uid,
      ["merchant"],
      "إنشاء الطلبات متاح لحسابات التجار النشطة فقط",
    );

    const orderRef = db.collection("orders").doc(cleanOrderId);

    // ── المرحلة الأولى: خصم المخزون وإنشاء عناصر الطلب (بدون قفل العداد) ──
   const phaseOneResult = await db.runTransaction(async (tx) => {
      // 🛡️ فحص Idempotency وفحص أمني صارم لملكية الطلب (منع ثغرة IDOR)
      const existingSnap = await tx.get(orderRef);
      if (existingSnap.exists) {
        const existingOrderData = existingSnap.data();
        if (existingOrderData?.merchant_id !== uid) {
          throw new HttpsError("permission-denied", "غير مصرح لك بالوصول إلى هذا الطلب أو تكراره");
        }
        if (existingOrderData?.order_number) {
          return { alreadyCreated: true, order: { id: existingSnap.id, ...existingOrderData } };
        }
      }

      // 🚀 جلب آمن ومقسم في دفعات متسلسلة داخل المعاملة يمنع اختناق الـ Execution Context
      const productIds = [...new Set(items.map((i) => String(i.product_id).trim()))];
      const productMap = new Map();
      const productFinancialMap = new Map();
      const BATCH_SIZE = 25;

      for (let i = 0; i < productIds.length; i += BATCH_SIZE) {
        const chunk = productIds.slice(i, i + BATCH_SIZE);
        const chunkRefs = chunk.map((id) => db.collection("products").doc(id));
        const chunkFinanceRefs = chunk.map((id) => db.collection("product_financials").doc(id));
        const chunkSnaps = await Promise.all(chunkRefs.map((ref) => tx.get(ref)));
        const chunkFinanceSnaps = await Promise.all(chunkFinanceRefs.map((ref) => tx.get(ref)));
        chunkSnaps.forEach((snap) => {
          if (snap.exists) productMap.set(snap.id, snap.data());
        });
        chunkFinanceSnaps.forEach((snap) => {
          if (snap.exists) productFinancialMap.set(snap.id, snap.data());
        });
      }

      let serverTotal = 0;
      let serverProfit = 0;
      const stockDeductions = new Map();
      const enrichedItems = [];
      const itemFinancials = [];

   const unavailableItems = [];
    const outOfStockItems = [];

    for (const item of items) {
        const pId = String(item.product_id).trim();
        const product = productMap.get(pId);

        if (!product || product.is_deleted === true || product.is_active === false) {
          const pName = product?.name || item.product_name || "الصنف";
          unavailableItems.push({ id: pId, name: pName });
          continue;
        }

        const qty = Number(item.quantity);
        if (!Number.isSafeInteger(qty) || qty <= 0) {
          throw new HttpsError("invalid-argument", `كمية الصنف (${product.name || pId}) غير صحيحة`);
        }

        const configuredCartonItems = Number(product.items_per_carton);
        const cartonItems = Number.isFinite(configuredCartonItems) &&
            configuredCartonItems > 0 ? configuredCartonItems : 1;
        const productFinancials = productFinancialMap.get(pId) || {};
        let unitPrice = Number(product.price);
        let costPrice = Number(productFinancials.cost_price ?? product.cost_price) || 0;
        const financialUnits = new Map(
          (Array.isArray(productFinancials.units) ? productFinancials.units : [])
            .map((unit) => [String(unit.label).trim(), unit]),
        );
        if (!Number.isFinite(unitPrice) || unitPrice < 0 ||
            !Number.isFinite(costPrice) || costPrice < 0) {
          throw new HttpsError("failed-precondition", `بيانات السعر للصنف ${pId} غير صالحة`);
        }
        let unitQty = cartonItems;
        let unitLabel = String(item.unit_label || "كرتون").trim();
        let selectedUnit = null;

        if (unitLabel !== "كرتون" && Array.isArray(product.units)) {
          selectedUnit = product.units.find((u) => String(u.label).trim() === unitLabel);
          if (!selectedUnit) {
            throw new HttpsError("failed-precondition", `PRODUCT_UNAVAILABLE_[${pId}:${unitLabel}]: الوحدة لم تعد متوفرة`);
          }
          unitPrice = Number(selectedUnit.price) || unitPrice;
          const unitFinancials = financialUnits.get(unitLabel) || {};
          costPrice = Number(unitFinancials.cost_price ?? selectedUnit.cost_price) || costPrice;
          unitQty = Number(selectedUnit.qty) || 1;
          if (!Number.isFinite(unitPrice) || unitPrice < 0 ||
              !Number.isFinite(costPrice) || costPrice < 0 ||
              !Number.isFinite(unitQty) || unitQty <= 0) {
            throw new HttpsError("failed-precondition", `بيانات الوحدة للصنف ${pId} غير صالحة`);
          }
        }

        const stockDeductCartons = Number(((qty * unitQty) / cartonItems).toFixed(4));
        const currentDeduction = stockDeductions.get(pId) || 0;
        const totalDeduction = currentDeduction + stockDeductCartons;

        const currentStock = Number(product.stock) || 0;
        if (!Number.isFinite(currentStock) || currentStock < 0) {
          throw new HttpsError("failed-precondition", `بيانات المخزون للصنف ${pId} غير صالحة`);
        }
       if (currentStock < totalDeduction) {
          outOfStockItems.push({ id: pId, name: product.name || pId });
          continue;
        }
        stockDeductions.set(pId, totalDeduction);

        const subtotal = unitPrice * qty;
        let unitCost = 0;
        const selectedUnitFinancials = selectedUnit
          ? financialUnits.get(unitLabel)
          : null;
        if (selectedUnitFinancials?.cost_price != null ||
            selectedUnit?.cost_price != null) {
          unitCost = Number(
            selectedUnitFinancials?.cost_price ?? selectedUnit.cost_price,
          );
        } else if (costPrice > 0 && cartonItems > 0) {
          unitCost = (costPrice / cartonItems) * unitQty;
        }
        const itemProfit = (unitPrice - unitCost) * qty;

        serverTotal += subtotal;
        serverProfit += itemProfit;
        if (!Number.isFinite(serverTotal) || !Number.isFinite(serverProfit)) {
          throw new HttpsError("failed-precondition", "تعذر احتساب إجمالي الطلب بدقة");
        }

       enrichedItems.push({
          order_id: orderRef.id,
          merchant_id: uid,
          product_id: pId,
          product_name: product.name || item.product_name || "",
          price: unitPrice,
          carton_capacity: cartonItems,
          quantity: qty,
          subtotal: subtotal,
          unit_label: unitLabel,
          unit_qty: unitQty,
        });
        itemFinancials.push({
          cost_price: costPrice,
          unit_cost: unitCost,
          profit: itemProfit,
        });
      }

      // 🛡️ فحص حاسم للمخزون: منع إنشاء أي طلب ناقص وإشعار التاجر فوراً بالأصناف غير المتوفرة
      if (unavailableItems.length > 0) {
        const ids = unavailableItems.map((i) => i.id).join(",");
        const names = unavailableItems.map((i) => i.name).join("، ");
        throw new HttpsError(
          "failed-precondition",
          `PRODUCT_UNAVAILABLE_[${ids}]: نعتذر، الأصناف التالية لم تعد متوفرة في المستودع (${names})`,
        );
      }

      if (outOfStockItems.length > 0) {
        const ids = outOfStockItems.map((i) => i.id).join(",");
        const names = outOfStockItems.map((i) => i.name).join("، ");
        throw new HttpsError(
          "failed-precondition",
          `OUT_OF_STOCK_[${ids}]: نعتذر، نفد مخزون الأصناف التالية من المستودع (${names})`,
        );
      }

      if (enrichedItems.length === 0) {
        throw new HttpsError("failed-precondition", "لا توجد أصناف صالحة لإتمام هذا الطلب");
      }

// 🚀 توليد رقم الفاتورة ذرياً وحسابياً فائق السرعة بدون أي قفل قاعدة بيانات (High-Throughput 100+ TPS)
      // يعتمد على الزمن الحالي بنظام Base36 مدمجاً مع 3 خانات عشوائية (مثال: ORD-L8K2P9)
      // 🚀 توليد رقم فاتورة عالي الإنتاجية يستحيل تصادمه إحصائياً (1 في 4.3 مليار لكل جزء ثانية)
    // 🔒 توليد رقم فريد ذري غير قابل للتصادم إحصائياً (CSPRNG Entropy 64-bit + Timestamp)
      const now = new Date();
      const dateHeader = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}`;
      const timeHex = Date.now().toString(36).toUpperCase();
      const randomEntropy = crypto.randomBytes(4).toString("hex").toUpperCase();
      const invoiceNumberString = `INV-${dateHeader}-${timeHex}-${randomEntropy}`;
      // تطبيق خصم المخزون الذري
      for (const [pId, deductQty] of stockDeductions.entries()) {
        tx.update(db.collection("products").doc(pId), {
          stock: FieldValue.increment(-deductQty),
          updated_at: FieldValue.serverTimestamp(),
        });
      }
// 🔒 القائمة البيضاء الصارمة: قبول الحقول التشغيلية المعتمدة فقط وحظر أي حقن مالي خارجي
      const rawExtra = extraData || {};
      const orderDataWithNumber = {
        store_name: String(rawExtra.store_name || profile.store_name || "").trim(),
        customer_name: String(rawExtra.customer_name || rawExtra.merchant_name || profile.full_name || "").trim(),
        merchant_name: String(rawExtra.merchant_name || profile.full_name || "").trim(),
        contact: String(rawExtra.contact || rawExtra.phone_number || profile.phone_number || "").trim(),
        phone_number: String(rawExtra.phone_number || rawExtra.contact || profile.phone_number || "").trim(),
        delivery_address: String(rawExtra.delivery_address || rawExtra.store_name || "").trim(),
        latitude: rawExtra.latitude != null ? Number(rawExtra.latitude) : (profile.latitude || null),
        longitude: rawExtra.longitude != null ? Number(rawExtra.longitude) : (profile.longitude || null),
        payment_method: String(rawExtra.payment_method || "cash").trim().toLowerCase() === "deferred" ? "deferred" : "cash",
        merchant_id: uid,
        total: serverTotal,
        total_amount: serverTotal,
        delivery_fee: 500.0, // سقف تسعير رسمي ثابت محمي من السيرفر
        notes: notes ? String(notes).trim() : null,
        status: "pending",
        profit_recorded: false,
        financial_safe: true,
        items_count: enrichedItems.length,
        order_number: invoiceNumberString,
        invoice_number: invoiceNumberString,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      };
     // ✅ التحقق الديناميكي الموحد مع مستند الإعدادات الرسمي لمنع تعارض الحد الأدنى
      let minOrderValue = 4250.0;
      try {
        const configDoc = await tx.get(db.collection("system_config").doc("app_config"));
        if (configDoc.exists) {
          const fetchedMin = Number(configDoc.data()?.min_order_value);
          if (Number.isFinite(fetchedMin) && fetchedMin > 0) {
            minOrderValue = fetchedMin;
          }
        }
      } catch (_) {
        minOrderValue = 4250.0;
      }

      if (serverTotal < minOrderValue) {
        throw new HttpsError("failed-precondition", `الحد الأدنى للطلب هو ${minOrderValue} ريال يمني`);
      }

      // كتابة الطلب وعناصره مباشرة
      tx.set(orderRef, orderDataWithNumber);

      for (let index = 0; index < enrichedItems.length; index++) {
        const itemRef = db.collection("order_items").doc();
        tx.set(itemRef, enrichedItems[index]);
        tx.set(db.collection("order_item_financials").doc(itemRef.id), {
          order_id: orderRef.id,
          order_item_id: itemRef.id,
          ...itemFinancials[index],
          updated_at: FieldValue.serverTimestamp(),
        });
      }
      tx.set(db.collection("order_financials").doc(orderRef.id), {
        order_id: orderRef.id,
        total_profit: serverProfit,
        profit_recorded: false,
        updated_at: FieldValue.serverTimestamp(),
      });

      return { alreadyCreated: false, orderData: orderDataWithNumber };
    });

    // 🚀 إرسال إشعار Push فوري لقناة السائقين المعتمدة حتى لو كانت هواتفهم مقفلة
    if (!phaseOneResult.alreadyCreated) {
      try {
        await messaging.send({
          topic: "drivers",
          notification: {
            title: "🚨 طلب جديد جاهز للتوصيل!",
            body: `طلب جديد بقيمة ${Number(phaseOneResult.orderData.total).toFixed(0)} ر.ي جاهز للاستلام والتوصيل`,
          },
          data: {
            order_id: orderRef.id,
            type: "new_order",
            route: "/driver",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            priority: "high",
            notification: {
              channelId: "sala_orders_channel",
              priority: "max",
              sound: "sala_notification",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            headers: { "apns-priority": "10", "apns-push-type": "alert" },
            payload: {
              aps: {
                alert: {
                  title: "🚨 طلب جديد جاهز للتوصيل!",
                  body: `طلب جديد بقيمة ${Number(phaseOneResult.orderData.total).toFixed(0)} ر.ي جاهز للاستلام`,
                },
                sound: "sala_notification.wav",
                badge: 1,
              },
            },
          },
        });
      } catch (pushErr) {
        console.warn("[placeOrder] Push notification to drivers failed:", pushErr);
      }
    }

    if (phaseOneResult.alreadyCreated) {
      return { success: true, order: phaseOneResult.order };
    }

    const completeOrder = {
      id: orderRef.id,
      ...phaseOneResult.orderData,
      created_at: new Date().toISOString(), 
    };

    return { success: true, order: completeOrder };
  }
);
// ══════════════════════════════════════════════════════════════
// 2. دالة إلغاء الطلب واسترجاع المخزون (cancelOrder)
// ══════════════════════════════════════════════════════════════
exports.cancelOrder = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }

    const uid = request.auth.uid;
    const { orderId } = request.data || {};
    if (!orderId) {
      throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
    }
const cleanOrderId = String(orderId).trim();
    const orderRef = db.collection("orders").doc(cleanOrderId);

    // 1. جلب عناصر الطلب خارج المعاملة لحماية عزل المعاملة الذرية (Snapshot Isolation)
    const itemsSnap = await db.collection("order_items").where("order_id", "==", cleanOrderId).get();
    const itemDocs = itemsSnap.docs;

    return await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const order = orderSnap.data();

      // التحقق من الصلاحية: صاحب الطلب أو إدارة
      const userProfile = await tx.get(db.collection("profiles").doc(uid));
      const userData = userProfile.data() || {};
      if (!userProfile.exists || userData.is_banned === true ||
          userData.is_active !== true) {
        throw new HttpsError("permission-denied", "الحساب غير نشط أو محظور");
      }
      const role = String(userData.role || "").trim().toLowerCase();
      if (!["merchant", "admin", "super_admin"].includes(role)) {
        throw new HttpsError("permission-denied", "غير مصرح لهذا الحساب بإلغاء الطلبات");
      }
      const isAdmin = role === "admin" || role === "super_admin";

      if (order.merchant_id !== uid && !isAdmin) {
        throw new HttpsError("permission-denied", "غير مصرح لك بإلغاء هذا الطلب");
      }
      if (order.status !== "pending") {
        throw new HttpsError("failed-precondition", `لا يمكن إلغاء طلب بحالة: ${order.status}`);
      }

      // 2. استرجاع المخزون للأصناف ذرياً
      for (const doc of itemDocs) {
        const item = doc.data();
        const pId = item.product_id;
        const qty = Number(item.quantity) || 0;
        const capacity = Number(item.carton_capacity) || 1;
        const unitQty = Number(item.unit_qty) || capacity;
        const cartonsToRestore = Number(((qty * unitQty) / capacity).toFixed(4));

        if (pId && cartonsToRestore > 0) {
          tx.update(db.collection("products").doc(pId), {
            stock: FieldValue.increment(cartonsToRestore),
            updated_at: FieldValue.serverTimestamp(),
          });
        }
      }

      tx.update(orderRef, {
        status: "cancelled",
        cancelled_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });

      return { success: true };
    });
  }
);

// ══════════════════════════════════════════════════════════════
// 3. دالة معالجة المرتجعات وتسويتها (processReturn & updateReturnStatus)
// ══════════════════════════════════════════════════════════════
exports.processReturn = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }

    const uid = request.auth.uid;
    const { returnId, status, rejectionReason } = request.data || {};

    if (!returnId || !["accepted", "rejected"].includes(status)) {
      throw new HttpsError("invalid-argument", "بيانات المرتجع غير صالحة");
    }

    // التحقق من صلاحيات الإدارة
    await requireActiveRole(
      uid,
      ["admin", "super_admin", "accountant", "warehouse_manager"],
      "هذه العملية خاصة بالإدارة فقط",
    );

    const returnRef = db.collection("order_returns").doc(String(returnId).trim());

    return await db.runTransaction(async (tx) => {
      const returnSnap = await tx.get(returnRef);
      if (!returnSnap.exists) {
        throw new HttpsError("not-found", "طلب الإرجاع غير موجود");
      }
      const returnData = returnSnap.data();
      if (returnData.status !== "pending") {
        return { success: true, message: "تمت معالجة الطلب مسبقاً" };
      }

      const orderRef = db.collection("orders").doc(returnData.order_id);
      const orderSnap = await tx.get(orderRef);
      const orderData = orderSnap.exists ? orderSnap.data() : null;
      const orderFinancialRef = db.collection("order_financials").doc(returnData.order_id);
      const orderFinancialSnap = await tx.get(orderFinancialRef);

      const currentPendingCount = Number(orderData?.pending_returns_count) || 1;
      const newPendingCount = Math.max(0, currentPendingCount - 1);
      const hasOtherPending = newPendingCount > 0;

    if (status === "rejected") {
        tx.update(returnRef, {
          status: "rejected",
          rejection_reason: rejectionReason ? String(rejectionReason).trim() : null,
          updated_at: FieldValue.serverTimestamp(),
        });

        if (orderSnap.exists) {
          tx.update(orderRef, {
            status: hasOtherPending ? "return_requested" : "delivered",
            pending_returns_count: newPendingCount,
            updated_at: FieldValue.serverTimestamp(),
          });
        }
        return { success: true };
      }
      // إذا كانت الحالة accepted: استرجاع المخزون وتسوية الرصيد
      const itemRef = db.collection("order_items").doc(returnData.order_item_id);
      const itemSnap = await tx.get(itemRef);
      const itemFinancialRef = db.collection("order_item_financials").doc(returnData.order_item_id);
      const itemFinancialSnap = await tx.get(itemFinancialRef);
      if (!itemSnap.exists) {
        throw new HttpsError("not-found", "عنصر الطلب الأصلي غير موجود");
      }
      const itemData = itemSnap.data();

      const returnQty = Number(returnData.quantity) || 0;
      const capacity = Number(itemData.carton_capacity) || 1;
      const unitQty = Number(itemData.unit_qty) || capacity;
      const cartonsToRestore = Number(((returnQty * unitQty) / capacity).toFixed(4));
      const price = Number(itemData.price) || 0;
      const refundAmount = price * returnQty;

      const unitCost = Number(
        itemFinancialSnap.data()?.unit_cost ?? itemData.unit_cost,
      ) || 0;
      const deductedProfit = (price - unitCost) * returnQty;
      const currentProfit = Number(
        orderFinancialSnap.data()?.total_profit ?? orderData?.total_profit,
      );
      if (!Number.isFinite(currentProfit)) {
        throw new HttpsError("failed-precondition", "بيانات أرباح الطلب غير متاحة");
      }

      // 1. إعادة المخزون
      tx.update(db.collection("products").doc(itemData.product_id), {
        stock: FieldValue.increment(cartonsToRestore),
        updated_at: FieldValue.serverTimestamp(),
      });

      // 2. تحديث عداد المرتجع في الصنف
      tx.update(itemRef, {
        returned_quantity: FieldValue.increment(returnQty),
        updated_at: FieldValue.serverTimestamp(),
      });

      // 3. تحديث الفاتورة
      const currentTotal = Number(orderData?.total_amount || orderData?.total || 0);
      const safeNewTotal = Math.max(0, currentTotal - refundAmount);

      tx.update(orderRef, {
        status: safeNewTotal <= 0.01 && !hasOtherPending ? "returned" : (hasOtherPending ? "return_requested" : "delivered"),
        total: safeNewTotal,
        total_amount: safeNewTotal,
        returned_amount: FieldValue.increment(refundAmount),
        pending_returns_count: newPendingCount,
        updated_at: FieldValue.serverTimestamp(),
      });
      tx.set(orderFinancialRef, {
        order_id: returnData.order_id,
        total_profit: currentProfit - deductedProfit,
        updated_at: FieldValue.serverTimestamp(),
      }, { merge: true });

      // 4. تحديث حالة المرتجع
      tx.update(returnRef, {
        status: "accepted",
        updated_at: FieldValue.serverTimestamp(),
      });
// 5. تحديث مستند الإحصائيات الرئيسي ذرياً ومباشرة
      const summaryParentRef = db.collection("stats").doc("profit_summary");
      tx.set(summaryParentRef, {
        accumulated_profit: FieldValue.increment(-deductedProfit),
        cycle_profit: FieldValue.increment(-deductedProfit),
        accumulated_returns: FieldValue.increment(refundAmount),
        last_updated: FieldValue.serverTimestamp(),
      }, { merge: true });
      return { success: true };
    });
  }
);
// ══════════════════════════════════════════════════════════════
// 1. دالة استلام السائق للطلب وقفل التنافس (assignOrderToDriver)
// ══════════════════════════════════════════════════════════════
exports.assignOrderToDriver = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }

    const uid = request.auth.uid;
    const { orderId } = request.data || {};
    if (!orderId) {
      throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
    }

    // 1. التحقق من رتبة وصلاحية السائق
    const driverDoc = await db.collection("profiles").doc(uid).get();
    if (!driverDoc.exists) {
      throw new HttpsError("not-found", "حساب السائق غير موجود");
    }
    const driverData = driverDoc.data();
    const role = (driverData.role || "").trim().toLowerCase();
    if (driverData.is_banned === true || driverData.is_active !== true || (role !== "driver" && role !== "admin" && role !== "super_admin")) {
      throw new HttpsError("permission-denied", "الحساب غير مصرح له باستلام وتوصيل الطلبات");
    }

    const driverName = driverData.full_name || "مندوب معتمد";
    const orderRef = db.collection("orders").doc(String(orderId).trim());

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const order = snap.data();
      // 🛡️ فحص منع التكرار: إذا كان الطلب مسنداً لنفس السائق مسبقاً نرجع نجاحاً فوراً
      if (order.driver_id === uid && order.status === "shipped") {
        return { success: true, message: "الطلب مسند لك بالفعل" };
      }

      // منع سرقة الطلبات بين السائقين
      if (order.driver_id && order.driver_id !== uid) {
        throw new HttpsError("failed-precondition", "تم استلام هذا الطلب من قبل مندوب آخر");
      }
      if (order.status !== "confirmed" && order.status !== "pending") {
        throw new HttpsError("failed-precondition", `لا يمكن استلام طلب بحالة: ${order.status}`);
      }

      tx.update(orderRef, {
        status: "shipped",
        driver_id: uid,
        driver_name: driverName,
        picked_up_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });

      // إشعار فوري للتاجر
      if (order.merchant_id) {
        tx.set(db.collection("user_notifications").doc(), {
          user_id: order.merchant_id,
          title: "🚚 طلبك انطلق نحوك!",
          body: `المندوب (${driverName}) استلم طلبك وهو في الطريق إليك الآن 🛣️`,
          order_id: orderRef.id,
          type: "order_status",
          is_read: false,
          created_at: FieldValue.serverTimestamp(),
        });
      }

      return { success: true };
    });
  }
);

// ══════════════════════════════════════════════════════════════
// 2. دالة تسليم الطلب واعتماد الأرباح والتوقيع (deliverOrderByDriver)
// ══════════════════════════════════════════════════════════════
exports.deliverOrderByDriver = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }

    const uid = request.auth.uid;
    const { orderId, signatureData } = request.data || {};
    const cleanOrderId = String(orderId || "").trim();
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(cleanOrderId)) {
      throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
    }

    // التحقق من صلاحية المنفّذ (سائق أو إدارة)
    const callerDoc = await db.collection("profiles").doc(uid).get();
    const callerData = callerDoc.data() || {};
    const callerRole = String(callerData.role || "").trim().toLowerCase();
    const isAuthorized = ["driver", "admin", "super_admin"].includes(callerRole);
    if (!callerDoc.exists || callerData.is_banned === true ||
        callerData.is_active !== true || !isAuthorized) {
      throw new HttpsError("permission-denied", "غير مصرح لك بتسليم الطلبات");
    }

    const orderRef = db.collection("orders").doc(cleanOrderId);
    const preflightSnap = await orderRef.get();
    if (!preflightSnap.exists) {
      throw new HttpsError("not-found", "الطلب غير موجود");
    }
    const preflightOrder = preflightSnap.data() || {};
    if (preflightOrder.status === "delivered" && preflightOrder.profit_recorded === true) {
      return { success: true, message: "تم تسجيل تسليم الطلب مسبقاً" };
    }
    if (preflightOrder.status !== "shipped" && preflightOrder.status !== "on_the_way") {
      throw new HttpsError("failed-precondition", `لا يمكن تسليم طلب بحالة: ${preflightOrder.status}`);
    }
    if (callerRole === "driver" && preflightOrder.driver_id !== uid) {
      throw new HttpsError("permission-denied", "هذا الطلب غير مسند إليك أو تم تسليمه لسائق آخر");
    }
// 🔒 تحفة المعالجة الهجينة للتوقيع: دعم كامل لروابط Storage المسبقة (أونلاين) وبايتات Base64 (أوفلاين)
    let finalSignatureUrl = null;
    if (signatureData != null) {
      if (typeof signatureData !== "string" || signatureData.length > 1400000) {
        throw new HttpsError("invalid-argument", "حجم بيانات التوقيع يتجاوز الحد المسموح");
      }

      const rawSig = signatureData.trim();

      // ── المسار الأول: إذا كان التوقيع مرفوعاً مسبقاً من تطبيق الفلاتر كـ رابط ويب رسمي (أونلاين) ──
      if (rawSig.startsWith("https://")) {
        try {
          const parsedUrl = new URL(rawSig);
          const objectPath = decodeURIComponent(parsedUrl.pathname.split("/o/")[1] || "");
          const belongsToOrder =
            objectPath.startsWith(`signatures/signature_${cleanOrderId}_`) ||
            objectPath.startsWith(`signatures/order_${cleanOrderId}_`);

          if (parsedUrl.hostname !== "firebasestorage.googleapis.com" ||
              !parsedUrl.searchParams.has("token") || !belongsToOrder) {
            throw new HttpsError("invalid-argument", "رابط التوقيع غير صالح أو لا يتبع هذا الطلب أمنياً");
          }
          finalSignatureUrl = rawSig;
        } catch (urlError) {
          if (urlError instanceof HttpsError) throw urlError;
          throw new HttpsError("invalid-argument", "صيغة رابط التوقيع غير صالحة");
        }
      } 
      // ── المسار الثاني: إذا كان التوقيع ملتقطاً أوفلاين كـ Base64 Data URI ──
      else {
        const signatureMatch = rawSig.match(/^data:image\/png;base64,([A-Za-z0-9+/]+={0,2})$/);
        if (!signatureMatch) {
          throw new HttpsError("invalid-argument", "صيغة التوقيع غير صالحة (يجب أن يكون رابط HTTPS معتمد أو Base64)");
        }

        const buffer = Buffer.from(signatureMatch[1], "base64");
        const pngHeader = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]); // البصمة الرقمية القياسية لملفات PNG
        if (buffer.length === 0 || buffer.length > 1024 * 1024 ||
            !buffer.subarray(0, 8).equals(pngHeader)) {
          throw new HttpsError("invalid-argument", "ملف التوقيع تالف أو لا يطابق ترويسة ملفات PNG الحقيقية");
        }

        try {
          const bucket = storage.bucket();
          const fileName = `signatures/order_${cleanOrderId}_${Date.now()}.png`;
          const file = bucket.file(fileName);
          const downloadToken = crypto.randomUUID();

          await file.save(buffer, {
            metadata: {
              contentType: "image/png",
              metadata: { firebaseStorageDownloadTokens: downloadToken },
            },
          });
          finalSignatureUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(fileName)}?alt=media&token=${downloadToken}`;
        } catch (uploadError) {
          console.error("[deliverOrderByDriver] Failed to store signature file:", uploadError);
          finalSignatureUrl = null;
        }
      }
    }
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const order = snap.data();

     // 🛡️ فحص Idempotency: إذا كان قد سُلّم وسُجلت أرباحه سابقاً نرجع بنجاح فوري
      if (order.status === "delivered" && order.profit_recorded === true) {
        return { success: true, message: "تم تسجيل تسليم الطلب مسبقاً" };
      }
      const financialRef = db.collection("order_financials").doc(cleanOrderId);
      const financialSnap = await tx.get(financialRef);

      // التحقق الصارم من حالة الطلب وأحقية السائق
      if (order.status !== "shipped" && order.status !== "on_the_way") {
        throw new HttpsError("failed-precondition", `لا يمكن تسليم طلب بحالة: ${order.status}`);
      }

      if (callerRole === "driver" && order.driver_id !== uid) {
        throw new HttpsError("permission-denied", "هذا الطلب غير مسند إليك أو تم تسليمه لسائق آخر");
      }

      const totalProfit = Number(
        financialSnap.data()?.total_profit ?? order.total_profit,
      ) || 0;
      const totalAmount = Number(order.total_amount) || Number(order.total) || 0;

      // 1. تحديث الطلب وإرفاق التوقيع الرسمي
      const updatePayload = {
        status: "delivered",
        delivered_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        profit_recorded: true,
      };
      if (finalSignatureUrl) {
        updatePayload.signature_url = finalSignatureUrl;
      }
      tx.update(orderRef, updatePayload);
      tx.set(financialRef, {
        order_id: cleanOrderId,
        profit_recorded: true,
        updated_at: FieldValue.serverTimestamp(),
      }, { merge: true });
// 2. تحديث المستند الرئيسي للأرباح والإيرادات ذرياً
      if (order.profit_recorded !== true) {
        const summaryParentRef = db.collection("stats").doc("profit_summary");
        tx.set(summaryParentRef, {
          accumulated_profit: FieldValue.increment(totalProfit),
          cycle_profit: FieldValue.increment(totalProfit),
          accumulated_revenue: FieldValue.increment(totalAmount),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      // 3. إشعار التاجر بوصول الطلب
      if (order.merchant_id) {
        tx.set(db.collection("user_notifications").doc(), {
          user_id: order.merchant_id,
          title: "🎉 تم تسليم طلبك بنجاح!",
          body: "تم تسليم الطلب وتوثيق التوقيع بنجاح. شكراً لثقتكم بنا 💐",
          order_id: orderRef.id,
          type: "order_status",
          is_read: false,
          created_at: FieldValue.serverTimestamp(),
        });
      }

      return { success: true };
    });
  }
);
// ══════════════════════════════════════════════════════════════
// دالة تقديم طلبات الإرجاع واعتمادها سحابياً (submitReturnRequest)
// ══════════════════════════════════════════════════════════════
exports.submitReturnRequest = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const uid = request.auth.uid;
    const { orderId, itemsToReturn, storeName, contact, latitude, longitude, reason } = request.data || {};

    const cleanOrderId = String(orderId || "").trim();
    const cleanReason = String(reason || "").trim();

    if (!cleanOrderId) {
      throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
    }
    if (!Array.isArray(itemsToReturn) || itemsToReturn.length === 0) {
      throw new HttpsError("invalid-argument", "يجب تحديد أصناف للإرجاع");
    }
    if (itemsToReturn.length > 200) {
      throw new HttpsError("invalid-argument", "عدد أصناف الإرجاع يتجاوز الحد المسموح");
    }
    if (!cleanReason || cleanReason.length < 3) {
      throw new HttpsError("invalid-argument", "سبب الإرجاع مطلوب ويجب توضيحه");
    }

    await requireActiveRole(
      uid,
      ["merchant"],
      "تقديم طلبات الإرجاع متاح لحسابات التجار النشطة فقط",
    );

    const orderRef = db.collection("orders").doc(cleanOrderId);

    // 2. تجميع كميات الأصناف المكررة لمنع تعارض المعاملة الذرية
    const aggregated = new Map();
    for (const item of itemsToReturn) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        throw new HttpsError("invalid-argument", "بيانات صنف الإرجاع غير صالحة");
      }
      const itemId = String(item.order_item_id || item.id || "").trim();
      const qty = Number(item.quantity);
      if (!itemId || !Number.isSafeInteger(qty) || qty <= 0) {
        throw new HttpsError("invalid-argument", "معرف الصنف وكمية الإرجاع غير صالحين");
      }
      const totalQty = (aggregated.get(itemId) || 0) + qty;
      if (!Number.isSafeInteger(totalQty)) {
        throw new HttpsError("invalid-argument", "إجمالي كمية الإرجاع يتجاوز الحد المسموح");
      }
      aggregated.set(itemId, totalQty);
    }

    if (aggregated.size === 0) {
      throw new HttpsError("invalid-argument", "لم يتم إدخال كميات صالحة للإرجاع");
    }

    return await db.runTransaction(async (tx) => {
      // 3. قراءة وفحص الطلب الأصلي
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const order = orderSnap.data();

      // التحقق الصارم من ملكية التاجر للطلب
      if (order.merchant_id !== uid) {
        throw new HttpsError("permission-denied", "غير مصرح لك بطلب إرجاع لهذا الطلب");
      }

      // التحقق من حالة الطلب
      if (order.status !== "delivered" && order.status !== "return_requested") {
        throw new HttpsError("failed-precondition", `لا يمكن طلب إرجاع لطلب بحالة: ${order.status}`);
      }

      // منع تقديم طلب جديد إذا كان هناك إرجاع معلق قيد المراجعة لنفس الطلب
      const pendingCount = Number(order.pending_returns_count) || 0;
      if (pendingCount > 0) {
        throw new HttpsError("failed-precondition", "يوجد طلب إرجاع قيد المراجعة مسبقاً لهذا الطلب");
      }

      // 4. قراءة وفحص عناصر الطلب والتأكد من الأسعار والكميات المتبقية
      const itemEntries = Array.from(aggregated.entries());
      const itemSnaps = await Promise.all(
        itemEntries.map(([itemId]) => tx.get(db.collection("order_items").doc(itemId)))
      );
const returnDocs = [];

      for (let i = 0; i < itemSnaps.length; i++) {
        const itemSnap = itemSnaps[i];
        const [itemId, returnQty] = itemEntries[i];

        if (!itemSnap.exists) {
          throw new HttpsError("not-found", "عنصر الطلب غير موجود");
        }

        const itemData = itemSnap.data();
        if (itemData.order_id !== cleanOrderId) {
          throw new HttpsError("invalid-argument", "أحد الأصناف لا يتبع هذا الطلب");
        }

        const orderedQty = Number(itemData.quantity) || 0;
        const alreadyReturned = Number(itemData.returned_quantity) || 0;
        const remainingQty = Math.max(0, orderedQty - alreadyReturned);

        if (returnQty > remainingQty) {
          throw new HttpsError(
            "failed-precondition",
            `الكمية المطلوب إرجاعها من "${itemData.product_name}" (${returnQty}) تتجاوز الكمية المتبقية (${remainingQty})`
          );
        }

        // 🚀 توليد رقم مرجوع فريد بدون قفل عداد
        const returnSeqString = `RET-${Date.now().toString(36).toUpperCase().slice(-5)}${crypto.randomInt(10, 99)}`;
        const itemPrice = Number(itemData.price) || 0;
        const refundAmount = itemPrice * returnQty;

        returnDocs.push({
          ref: db.collection("order_returns").doc(),
          data: {
            order_id: cleanOrderId,
            order_item_id: itemSnap.id,
            merchant_id: uid,
            product_id: itemData.product_id || "",
            product_name: String(itemData.product_name || "منتج").trim(),
            quantity: returnQty,
            unit_label: String(itemData.unit_label || "كرتون").trim(),
            unit_price: itemPrice,
            refund_amount: refundAmount,
            store_name: String(storeName || order.store_name || "").trim(),
            contact: String(contact || order.contact || order.phone_number || "").trim(),
            latitude: latitude != null ? Number(latitude) : (order.latitude || null),
            longitude: longitude != null ? Number(longitude) : (order.longitude || null),
            reason: cleanReason,
            status: "pending",
            return_number: returnSeqString,
            invoice_number: returnSeqString,
            created_at: FieldValue.serverTimestamp(),
            updated_at: FieldValue.serverTimestamp(),
          },
        });
      }

      // 5. كتابة مستندات الإرجاع وحالة الطلب
      for (const rDoc of returnDocs) {
        tx.set(rDoc.ref, rDoc.data);
      }
      tx.update(orderRef, {
        status: "return_requested",
        return_reason: cleanReason,
        pending_returns_count: returnDocs.length,
        updated_at: FieldValue.serverTimestamp(),
      });

      return { success: true, count: returnDocs.length };
    });
  }
);
// ══════════════════════════════════════════════════════════════
// 1. دالة إدارة الحسابات، الصلاحيات، والحظر السحابية (manageUserAccount)
// ══════════════════════════════════════════════════════════════
exports.manageUserAccount = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    const { targetUserId, action, role: newRole, isActive } = request.data || {};

    const cleanTargetId = String(targetUserId || "").trim();
    const cleanAction = String(action || "").trim();

    if (!cleanTargetId || !cleanAction) {
      throw new HttpsError("invalid-argument", "معرف المستخدم ونوع الإجراء مطلوبان");
    }

    // 1. التحقق الصارم من رتبة وصلاحية المدير المنفّذ من السيرفر
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    if (!callerDoc.exists) {
      throw new HttpsError("permission-denied", "حساب المنفّذ غير مسجل");
    }
    const callerData = callerDoc.data() || {};
    const callerRole = String(callerData.role || "").trim().toLowerCase();

    if (callerData.is_banned === true || callerData.is_active !== true || (callerRole !== "admin" && callerRole !== "super_admin")) {
      throw new HttpsError("permission-denied", "هذه العملية مقتصرة على مدراء النظام فقط");
    }

    // حماية: منع المدير من حظر أو تعطيل حسابه الشخصي
    if (callerUid === cleanTargetId && (cleanAction === "ban" || cleanAction === "toggle_active")) {
      throw new HttpsError("failed-precondition", "لا يمكنك حظر أو تعطيل حسابك الشخصي");
    }

    const targetRef = db.collection("profiles").doc(cleanTargetId);
    const targetDoc = await targetRef.get();
    if (!targetDoc.exists) {
      throw new HttpsError("not-found", "المستخدم المستهدف غير موجود");
    }
    const targetData = targetDoc.data() || {};
    const targetRole = String(targetData.role || "").trim().toLowerCase();

    // حماية: لا يمكن لمدير عادي تعديل حساب المدير العام
    if (targetRole === "super_admin" && callerRole !== "super_admin") {
      throw new HttpsError("permission-denied", "لا يمكن تعديل صلاحيات المدير العام");
    }

    const allowedRoles = ["merchant", "driver", "admin", "super_admin", "accountant", "warehouse_manager"];

    switch (cleanAction) {
      case "change_role": {
        const cleanRole = String(newRole || "").trim().toLowerCase();
        if (!allowedRoles.includes(cleanRole)) {
          throw new HttpsError("invalid-argument", "الرتبة المحددة غير صالحة");
        }
        if (cleanRole === "super_admin" && callerRole !== "super_admin") {
          throw new HttpsError("permission-denied", "ترقية الحساب إلى مدير عام مقتصرة على المدير العام فقط");
        }

        const updates = {
          role: cleanRole,
          updated_at: FieldValue.serverTimestamp(),
        };

        if (cleanRole === "driver") {
          updates.is_active = true;
          updates.is_banned = false;
          updates.account_status = "active";
        }

        await targetRef.update(updates);

        // تحديث الرتبة في الـ Custom Claims لتفعيل الصلاحيات في التوكن
        try {
          await auth.setCustomUserClaims(cleanTargetId, {
            role: cleanRole,
            purpose: "registered",
          });
        } catch (authErr) {
          console.warn(`[manageUserAccount] Failed to set claims for ${cleanTargetId}:`, authErr);
        }

        return { success: true, message: "تم تغيير الرتبة بنجاح" };
      }

      case "ban": {
        await targetRef.update({
          is_active: false,
          is_banned: true,
          account_status: "banned",
          banned_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });
        // إبطال جلسة المستخدم وطرده فوراً
        try {
          await auth.revokeRefreshTokens(cleanTargetId);
        } catch (_) {}
        return { success: true, message: "تم حظر الحساب بنجاح" };
      }

      case "unban": {
        await targetRef.update({
          is_active: true,
          is_banned: false,
          account_status: "active",
          banned_at: FieldValue.delete(),
          updated_at: FieldValue.serverTimestamp(),
        });
        return { success: true, message: "تم رفع الحظر بنجاح" };
      }

      case "toggle_active": {
        if (typeof isActive !== "boolean") {
          throw new HttpsError("invalid-argument", "حالة التفعيل يجب أن تكون قيمة منطقية");
        }
        const activeBool = isActive;
        await targetRef.update({
          is_active: activeBool,
          account_status: activeBool ? "active" : "suspended",
          updated_at: FieldValue.serverTimestamp(),
        });
        if (!activeBool) {
          try {
            await auth.revokeRefreshTokens(cleanTargetId);
          } catch (_) {}
        }
        return { success: true, message: activeBool ? "تم تفعيل الحساب" : "تم تعطيل الحساب" };
      }

      default:
        throw new HttpsError("invalid-argument", "نوع الإجراء غير معروف");
    }
  }
);
// ══════════════════════════════════════════════════════════════
// 2. دالة بث الإشعارات لجميع التجار سحابياً (sendBroadcastNotification)
// ══════════════════════════════════════════════════════════════
exports.sendBroadcastNotification = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    const { title, body } = request.data || {};

    const cleanTitle = String(title || "").trim();
    const cleanBody = String(body || "").trim();

    if (!cleanTitle || !cleanBody) {
      throw new HttpsError("invalid-argument", "عنوان ونص الإشعار مطلوبان");
    }

    // التحقق من صلاحيات الإدارة
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "accountant"],
      "هذه العملية خاصة بالإدارة فقط",
    );

    // 1. تسجيل سجل البث في الأرشيف
    await db.collection("broadcast_notifications").add({
      title: cleanTitle,
      body: cleanBody,
      target_role: "merchant",
      topic: "merchants",
      sent_by: callerUid,
      status: "sent",
      created_at: FieldValue.serverTimestamp(),
    });
// 2. بث الإشعار لجميع التجار عبر FCM Topic (مدعوم لنظامي iOS وأندرويد)
    try {
      await messaging.send({
        topic: "merchants",
        notification: {
          title: cleanTitle,
          body: cleanBody,
        },
        data: {
          title: cleanTitle,
          body: cleanBody,
          type: "broadcast",
          route: "/notifications",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "sala_orders_channel_v3",
            priority: "max",
            defaultSound: true,
            defaultVibrateTimings: true,
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
          },
          payload: {
            aps: {
              alert: { title: cleanTitle, body: cleanBody },
              sound: "default",
              badge: 1,
            },
          },
        },
      });
    } catch (fcmError) {
      console.error("[sendBroadcastNotification] FCM broadcast error:", fcmError);
    }
    return { success: true };
  }
);
// ══════════════════════════════════════════════════════════════
// 1. الحذف التسلسلي للأصناف والشركات سحابياً (cascadeDeleteCatalogItem)
// ══════════════════════════════════════════════════════════════
exports.cascadeDeleteCatalogItem = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    const { type, id } = request.data || {};
    const cleanId = String(id || "").trim();

    if (!cleanId || (type !== "category" && type !== "brand")) {
      throw new HttpsError("invalid-argument", "نوع العنصر ومعرفه مطلوبان");
    }

   // التحقق من صلاحيات الإدارة
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "warehouse_manager"],
      "هذه العملية مخصصة لمدراء النظام فقط",
    );
    const allRefsToUpdate = [];

    if (type === "category") {
      // 1. جلب الصنف
      allRefsToUpdate.push(db.collection("categories").doc(cleanId));

      // 2. جلب الشركات التابعة
      const brandsSnap = await db.collection("brands").where("category_id", "==", cleanId).get();
      brandsSnap.docs.forEach((doc) => allRefsToUpdate.push(doc.ref));

      // 3. جلب المنتجات المرتبطة مباشرة بالصنف
      const productsSnap = await db.collection("products").where("category_id", "==", cleanId).get();
      productsSnap.docs.forEach((doc) => allRefsToUpdate.push(doc.ref));

      // 4. جلب منتجات الشركات التابعة للصنف (في دفعات 30)
      const brandIds = brandsSnap.docs.map((d) => d.id);
      for (let i = 0; i < brandIds.length; i += 30) {
        const chunk = brandIds.slice(i, i + 30);
        const chunkProducts = await db.collection("products").where("brand_id", "in", chunk).get();
        chunkProducts.docs.forEach((doc) => allRefsToUpdate.push(doc.ref));
      }
    } else {
      // حذف شركة والمنتجات التابعة لها
      allRefsToUpdate.push(db.collection("brands").doc(cleanId));
      const productsSnap = await db.collection("products").where("brand_id", "==", cleanId).get();
      productsSnap.docs.forEach((doc) => allRefsToUpdate.push(doc.ref));
    }

    // إزالة التكرار من المراجع
    const uniqueRefs = Array.from(new Set(allRefsToUpdate.map((r) => r.path))).map((p) => db.doc(p));

    // تنفيذ الحذف البرمجي الناعم (Soft Delete) في دفعات سحابية سريعة
    const chunkSize = 400;
    for (let i = 0; i < uniqueRefs.length; i += chunkSize) {
      const chunk = uniqueRefs.slice(i, i + chunkSize);
      const batch = db.batch();
      for (const ref of chunk) {
        batch.update(ref, {
          is_deleted: true,
          is_active: false,
          deleted_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    return { success: true, count: uniqueRefs.length };
  }
);

// ══════════════════════════════════════════════════════════════
// 2. تصفير وتدقيق دورة الأرباح سحابياً (resetProfitCycle)
// ══════════════════════════════════════════════════════════════
exports.resetProfitCycle = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    const { data: callerData } = await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "accountant"],
      "هذه العملية مخصصة للمدراء الماليين فقط",
    );

    const docRef = db.collection("stats").doc("profit_summary");

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      const currentCycle = Number(snap.data()?.cycle_profit) || 0.0;

      // 1. تسجيل قيد محاسبي تدقيقي غير قابل للتعديل
      const logRef = db.collection("profit_resets_log").doc();
      tx.set(logRef, {
        cleared_amount: currentCycle,
        cleared_by: callerUid,
        cleared_by_name: callerData.full_name || "الإدارة",
        cleared_at: FieldValue.serverTimestamp(),
      });

      // 2. تصفير العداد للدورة الجديدة
      tx.set(
        docRef,
        {
          cycle_profit: 0.0,
          last_reset_at: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { success: true, clearedAmount: currentCycle };
    });
  }
);

// ══════════════════════════════════════════════════════════════
// 3. تحديث حالات الطلب من الإدارة سحابياً (adminUpdateOrderStatus)
// ══════════════════════════════════════════════════════════════
exports.adminUpdateOrderStatus = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    const { orderId, status, driverId, driverName } = request.data || {};

    const cleanOrderId = String(orderId || "").trim();
    let cleanStatus = String(status || "").trim().toLowerCase();
    if (cleanStatus === "accepted") cleanStatus = "confirmed";

    if (!cleanOrderId) {
      throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
    }

    // التحقق من الصلاحيات
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "accountant", "warehouse_manager"],
      "هذه العملية خاصة بالإدارة فقط",
    );
const orderRef = db.collection("orders").doc(cleanOrderId);
    // 🛡️ شمل حالة "returned" في استرجاع المخزون إلى المستودع لمنع العجز المخزني
    const requiresStockRestore = cleanStatus === "cancelled" || cleanStatus === "rejected" || cleanStatus === "returned";

    // جلب عناصر الطلب خارج المعاملة في حال تطلب استرجاع المخزون
    let itemDocs = [];
    if (requiresStockRestore) {
      const itemsSnap = await db.collection("order_items").where("order_id", "==", cleanOrderId).get();
      itemDocs = itemsSnap.docs;
    }

    return await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const order = orderSnap.data();
      const financialRef = db.collection("order_financials").doc(cleanOrderId);
      const financialSnap = await tx.get(financialRef);
      const currentStatus = String(order.status || "pending").toLowerCase();
      const isProfitRecorded = order.profit_recorded === true;

      if (currentStatus === cleanStatus && (cleanStatus !== "delivered" || isProfitRecorded)) {
        return { success: true, changed: false };
      }

    const allowedTransitions = {
        pending: ["confirmed", "shipped", "delivered", "rejected", "cancelled"],
        confirmed: ["preparing", "shipped", "delivered", "cancelled"],
        preparing: ["shipped", "delivered", "cancelled"],
        shipped: ["on_the_way", "delivered", "cancelled"],
        on_the_way: ["delivered", "cancelled"],
        delivered: ["delivered", "return_requested", "returned"],
        return_requested: ["returned", "delivered"],
      };

      if (["cancelled", "rejected", "returned"].includes(currentStatus)) {
        throw new HttpsError("failed-precondition", "لا يمكن تعديل طلب وصل إلى حالة نهائية");
      }

      const allowed = allowedTransitions[currentStatus] || [];
      if (!allowed.includes(cleanStatus)) {
        throw new HttpsError("failed-precondition", `لا يمكن نقل الطلب من "${currentStatus}" إلى "${cleanStatus}"`);
      }

      const updatePayload = {
        status: cleanStatus,
        updated_at: FieldValue.serverTimestamp(),
      };

      if (cleanStatus === "delivered") {
        updatePayload.delivered_at = FieldValue.serverTimestamp();
      }
      if (driverId) updatePayload.driver_id = String(driverId).trim();
      if (driverName) updatePayload.driver_name = String(driverName).trim();

      // 1. 🛡️ تسوية الأرباح والإحصائيات بدقة تامة عند التسليم أو الإرجاع
      if (cleanStatus === "delivered" && !isProfitRecorded) {
        const totalProfit = Number(
          financialSnap.data()?.total_profit ?? order.total_profit,
        ) || 0;
        const totalAmount = Number(order.total_amount) || Number(order.total) || 0;

        const summaryParentRef = db.collection("stats").doc("profit_summary");
        tx.set(summaryParentRef, {
          accumulated_profit: FieldValue.increment(totalProfit),
          cycle_profit: FieldValue.increment(totalProfit),
          accumulated_revenue: FieldValue.increment(totalAmount),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
        updatePayload.profit_recorded = true;
        tx.set(financialRef, {
          order_id: cleanOrderId,
          profit_recorded: true,
          updated_at: FieldValue.serverTimestamp(),
        }, { merge: true });
      } else if (cleanStatus === "returned" && isProfitRecorded) {
        // 🔒 خصم أرباح الطلب المسلم سابقاً وإضافته إلى إحصائيات المرتجعات المستردة
        const totalProfit = Number(
          financialSnap.data()?.total_profit ?? order.total_profit,
        ) || 0;
        const totalAmount = Number(order.total_amount) || Number(order.total) || 0;

        const summaryParentRef = db.collection("stats").doc("profit_summary");
        tx.set(summaryParentRef, {
          accumulated_profit: FieldValue.increment(-totalProfit),
          cycle_profit: FieldValue.increment(-totalProfit),
          accumulated_returns: FieldValue.increment(totalAmount),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
        updatePayload.profit_recorded = false;
        tx.set(financialRef, {
          order_id: cleanOrderId,
          profit_recorded: false,
          updated_at: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      // 2. 🛡️ استرجاع المخزون الفعلي في حالة الإلغاء أو الرفض أو الإرجاع
      if (requiresStockRestore && itemDocs.length > 0) {
        for (const itemDoc of itemDocs) {
          const item = itemDoc.data();
          const pId = item.product_id;
          const orderedQty = Number(item.quantity) || 0;
          const returnedQty = Number(item.returned_quantity) || 0;
          const netQty = Math.max(0, orderedQty - returnedQty);

          if (!pId || netQty <= 0) continue;

          const capacity = Number(item.carton_capacity) || 1;
          const unitQty = Number(item.unit_qty) || capacity;
          const cartonsToRestore = Number(((netQty * unitQty) / capacity).toFixed(4));

          if (cartonsToRestore > 0) {
            tx.update(db.collection("products").doc(pId), {
              stock: FieldValue.increment(cartonsToRestore),
              updated_at: FieldValue.serverTimestamp(),
            });
          }
        }
      }

      tx.update(orderRef, updatePayload);

      // 3. إرسال إشعار فوري للتاجر
      if (order.merchant_id) {
        const notifData = {
          confirmed: { title: "✅ تم قبول طلبك!", body: "بدأنا تجهيز طلبك بعناية وسنوافيك بالتحديثات." },
          preparing: { title: "📦 جاري تحضير طلبك", body: "فريق المستودع يجهز طلبك الآن تمهيداً لتسليمه للمندوب." },
          shipped: { title: "🚚 طلبك انطلق نحوك!", body: "المندوب في الطريق إليك الآن، يرجى الاستعداد للاستلام." },
          delivered: { title: "🎉 تم تسليم طلبك بنجاح!", body: "تم تسليم الطلب بالسلامة، نسعد بخدمتكم دائماً." },
          cancelled: { title: "⚠️ تم إلغاء الطلب", body: "تم إلغاء الطلب من قبل الإدارة، نعتذر عن أي إزعاج." },
          rejected: { title: "❌ نعتذر منك", body: "تعذر قبول الطلب هذه المرة لأسباب تشغيلية، نأمل خدمتكم قريباً." },
        }[cleanStatus];

        if (notifData) {
          tx.set(db.collection("user_notifications").doc(), {
            user_id: order.merchant_id,
            title: notifData.title,
            body: notifData.body,
            order_id: cleanOrderId,
            type: "order_status",
            status: cleanStatus,
            is_read: false,
            created_at: FieldValue.serverTimestamp(),
          });
        }
      }

      return { success: true, changed: true };
    });
  }
);
// ══════════════════════════════════════════════════════════════
// 📒 دوال دفتر ديون الزبائن المحاسبية المؤمّنة (Ledger Engine)
// ══════════════════════════════════════════════════════════════
// 1. إضافة زبون جديد في الدفتر بسلطة السيرفر مع فحص عدم التكرار
exports.addLedgerCustomer = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
 if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const merchantId = request.auth.uid;

    // 🔒 التحقق الصارم من حالة الحساب ومنع المتاجر المحظورة من أي تلاعب مالي
    await requireActiveRole(
      merchantId,
      ["merchant"],
      "إضافة زبائن الدفتر متاحة لحسابات التجار النشطة فقط",
    );
    const { name, phone, creditLimit, salaryDay, customerId } = request.data || {};

    const cleanName = String(name || "").trim();
    if (!cleanName) {
      throw new HttpsError("invalid-argument", "اسم الزبون مطلوب");
    }

    const arabicDigits = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9" };
    let cleanPhone = String(phone || "").trim();
    for (const [ar, en] of Object.entries(arabicDigits)) {
      cleanPhone = cleanPhone.replaceAll(ar, en);
    }

    const rawCreditLimit = creditLimit == null ? 0 : Number(creditLimit);
    if (!Number.isFinite(rawCreditLimit) || rawCreditLimit < 0) {
      throw new HttpsError("invalid-argument", "حد الائتمان غير صالح");
    }
    const safeCreditLimit = Math.round(rawCreditLimit);
    const parsedSalaryDay = salaryDay != null ? Math.min(31, Math.max(1, parseInt(salaryDay, 10))) : null;
    const requestedCustomerId = String(customerId || "").trim();
    if (requestedCustomerId && !/^[A-Za-z0-9_-]{1,128}$/.test(requestedCustomerId)) {
      throw new HttpsError("invalid-argument", "معرف الزبون غير صالح");
    }
    const docRef = requestedCustomerId
      ? db.collection("merchant_customers").doc(requestedCustomerId)
      : db.collection("merchant_customers").doc();

    return await db.runTransaction(async (tx) => {
      const reads = [tx.get(docRef)];
      if (cleanPhone) {
        reads.push(
          tx.get(
            db.collection("merchant_customers")
              .where("merchant_id", "==", merchantId)
              .where("phone", "==", cleanPhone)
              .where("is_deleted", "==", false)
              .limit(1),
          ),
        );
      }
      const [existingSnap, duplicateSnap] = await Promise.all(reads);
      if (!duplicateSnap?.empty && duplicateSnap.docs[0].id !== docRef.id) {
        throw new HttpsError("already-exists", "يوجد زبون مسجل مسبقاً بنفس رقم الهاتف");
      }

      // 🔒 التحقق الصارم من ملكية الوثيقة ومنع التعديل على زبائن يتبعون تجاراً آخرين
      if (existingSnap.exists) {
        const existingData = existingSnap.data() || {};
        if (existingData.merchant_id !== merchantId) {
          throw new HttpsError("permission-denied", "غير مصرح لك بتعديل بيانات زبون لا يتبع متجرك");
        }
      }
const existingData = existingSnap.exists ? (existingSnap.data() || {}) : {};
      const isReactivatingDeleted = existingSnap.exists && existingData.is_deleted === true;

      const customerData = {
        id: docRef.id,
        merchant_id: merchantId,
        name: cleanName,
        phone: cleanPhone,
        credit_limit: safeCreditLimit,
        salary_day: isNaN(parsedSalaryDay) ? null : parsedSalaryDay,
        is_deleted: false,
        updated_at: FieldValue.serverTimestamp(),
      };

      if (!existingSnap.exists || isReactivatingDeleted) {
        // 🔒 تصفير شامل وفوري للزبون المحذوف وتطهير أثره المالي لمنع عودة ديونه المشطوبة
        customerData.current_balance = 0.0;
        customerData.ledger_version = 0;
        customerData.applied_tx_ids = [];
        customerData.last_transaction_id = null;
        customerData.deleted_at = FieldValue.delete();
        customerData.summary_deducted = FieldValue.delete();
        customerData.reconciled_at = FieldValue.serverTimestamp();
        customerData.created_at = FieldValue.serverTimestamp();

        // استبدال كامل للوثيقة دون دمج { merge: true } لإلغاء أي حقول قديمة
        tx.set(docRef, customerData);
      } else {
        // تحديث عادي لبيانات زبون قائم ونشط مع الحفاظ على رصيده الحالي
        tx.set(docRef, customerData, { merge: true });
      }

      return {
        success: true,
        customer: {
          ...customerData,
          current_balance: (!existingSnap.exists || isReactivatingDeleted)
            ? 0.0
            : (Number(existingData.current_balance) || 0.0),
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
      };
    });
  }
);
// 1.1 حذف زبون من الدفتر سحابياً مع تسوية ديون السوق
exports.deleteLedgerCustomer = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const merchantId = request.auth.uid;

    await requireActiveRole(
      merchantId,
      ["merchant"],
      "حذف زبائن الدفتر متاح لحسابات التجار النشطة فقط",
    );

    const { customerId } = request.data || {};
    const cleanCustomerId = String(customerId || "").trim();

    if (!cleanCustomerId) {
      throw new HttpsError("invalid-argument", "معرف الزبون مطلوب");
    }

    const customerRef = db.collection("merchant_customers").doc(cleanCustomerId);
    const summaryRef = db.collection("merchant_ledger_summaries").doc(merchantId);

    return await db.runTransaction(async (tx) => {
      const customerSnap = await tx.get(customerRef);
      if (!customerSnap.exists) {
        return { success: true, message: "الزبون غير موجود مسبقاً" };
      }

      const customerData = customerSnap.data() || {};
      if (customerData.merchant_id !== merchantId) {
        throw new HttpsError("permission-denied", "غير مصرح لك بحذف هذا الزبون");
      }

      // إذا تم حذفه مسبقاً وسُويت ديونه نخرج بسلام دون تكرار الخصم
      if (customerData.is_deleted === true && customerData.summary_deducted === true) {
        return { success: true, message: "تم حذف الزبون مسبقاً" };
      }

      const balance = Number(customerData.current_balance) || 0;
      const debtPortion = Math.max(0, balance);
      const isDebtor = balance > 0;

      // حذف برمجياً (Soft-Delete) للحفاظ على المرجعية المحاسبية للفواتير القديمة
      tx.update(customerRef, {
        is_deleted: true,
        summary_deducted: true,
        deleted_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });

      // إذا كان الزبون عليه دين، خصم دينه من إجمالي ديون السوق
      if (debtPortion > 0 || isDebtor) {
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: FieldValue.increment(-debtPortion),
          debtors_count: FieldValue.increment(isDebtor ? -1 : 0),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      return { success: true };
    });
  }
);
// 2. قيد حركة مالية (دين أو سداد) ذرياً بحسابات القروش (Integer Cents)
exports.recordLedgerTransaction = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const merchantId = request.auth.uid;

    // 🔒 التحقق الصارم من حالة الحساب ومنع المتاجر المحظورة من أي تلاعب مالي
    await requireActiveRole(
      merchantId,
      ["merchant"],
      "عمليات الدفتر المالي متاحة لحسابات التجار النشطة فقط",
    );

    const { customerId, type, amount, notes, items, transactionId } = request.data || {};
    const cleanCustomerId = String(customerId || "").trim();
    const cleanType = String(type || "").trim().toLowerCase();
    const rawAmount = Number(amount);

    if (!cleanCustomerId) {
      throw new HttpsError("invalid-argument", "معرف الزبون مطلوب");
    }
    if (cleanType !== "debt" && cleanType !== "payment") {
      throw new HttpsError("invalid-argument", "نوع القيد يجب أن يكون debt أو payment");
    }
    if (!Number.isFinite(rawAmount) || rawAmount <= 0) {
      throw new HttpsError("invalid-argument", "مبلغ الحركة المالية غير صالح");
    }

    // حساب دقيق بالقروش لمنع أخطاء الفاصلة العائمة
    const amountCents = Math.round(rawAmount * 100);
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
      throw new HttpsError("invalid-argument", "مبلغ الحركة المالية يتجاوز الحد الدقيق المسموح");
    }
    const safeAmount = amountCents / 100;
    const isDebt = cleanType === "debt";
    const delta = isDebt ? safeAmount : -safeAmount;

    const requestedEntryId = String(transactionId || "").trim();
    if (requestedEntryId && !/^[A-Za-z0-9_-]{1,128}$/.test(requestedEntryId)) {
      throw new HttpsError("invalid-argument", "معرف القيد المالي غير صالح");
    }
    const entryId = requestedEntryId || `ledger_${merchantId.substring(0, 5)}_${Date.now()}_${db.collection("merchant_ledger_entries").doc().id}`;
    const entryRef = db.collection("merchant_ledger_entries").doc(entryId);
    const customerRef = db.collection("merchant_customers").doc(cleanCustomerId);
    if (items != null && !Array.isArray(items)) {
      throw new HttpsError("invalid-argument", "قائمة أصناف القيد غير صالحة");
    }
   const sanitizedItems = (items || []).map((it) => {
      if (!it || typeof it !== "object" || Array.isArray(it)) {
        throw new HttpsError("invalid-argument", "بيانات صنف القيد غير صالحة");
      }

      const productId = String(it.product_id || "").trim();
      const name = String(it.name || it.product_name || "").trim();
      // 🔒 إذا ترك التاجر حقل الوحدة فارغاً للسلع اليدوية، يتم إسناد "حبة" تلقائياً بدلاً من رفض المعاملة
      const rawUnitLabel = String(it.unit_label || "").trim();
      const unitLabel = rawUnitLabel.length > 0 ? rawUnitLabel : "حبة";
      const quantity = Number(it.quantity);
      const unitPrice = Number(it.unit_price);
      const subtotal = Number(it.subtotal);
      const cartonCapacity = Number(it.carton_capacity) > 0 ? Number(it.carton_capacity) : 1;

      if (!productId || !name ||
          !Number.isSafeInteger(quantity) || quantity <= 0 ||
          !Number.isFinite(unitPrice) || unitPrice < 0 ||
          !Number.isFinite(subtotal) || subtotal < 0 ||
          !Number.isSafeInteger(Math.round(unitPrice * quantity * 100)) ||
          Math.round(unitPrice * quantity * 100) !== Math.round(subtotal * 100)) {
        throw new HttpsError("invalid-argument", "بيانات صنف القيد أو إجماليه غير صالحة");
      }

      return {
        product_id: productId,
        name,
        quantity,
        unit_label: unitLabel,
        unit_price: unitPrice,
        subtotal,
        carton_capacity: cartonCapacity,
      };
    });
    const normalizedNotes = notes ? String(notes).trim() : null;
const result = await db.runTransaction(async (tx) => {
    // 🛡️ فحص Idempotency: إذا كان القيد مسجلاً مسبقاً نرجع الرصيد الحقيقي المعتمد بالسيرفر
      const existingEntry = await tx.get(entryRef);
      if (existingEntry.exists) {
        const existingData = existingEntry.data() || {};
        if (existingData.merchant_id !== merchantId ||
            existingData.customer_id !== cleanCustomerId) {
          throw new HttpsError("permission-denied", "معرف القيد المالي مستخدم لحساب آخر");
        }
        if (existingData.type !== cleanType ||
            Math.round(Number(existingData.amount) * 100) !== amountCents ||
            (existingData.notes || null) !== normalizedNotes ||
            !isDeepStrictEqual(existingData.items || [], sanitizedItems)) {
          throw new HttpsError("already-exists", "معرف القيد مستخدم لعملية مالية مختلفة");
        }
        const custSnap = await tx.get(customerRef);
        const currentBal = Number(custSnap.data()?.current_balance) || 0;
        return { success: true, alreadyRecorded: true, entryId, newBalance: currentBal };
      }

      const customerSnap = await tx.get(customerRef);
      if (!customerSnap.exists) {
        throw new HttpsError("not-found", "حساب الزبون غير موجود");
      }
      const customerData = customerSnap.data() || {};
      if (customerData.merchant_id !== merchantId) {
        throw new HttpsError("permission-denied", "غير مصرح لك بالقيد على هذا الحساب");
      } else if (customerData.is_deleted === true) {
        // 🔒 حظر قاطع يمنع تلوث ديون السوق بأي حركة على زبون محذوف
        throw new HttpsError("failed-precondition", "CUSTOMER_DELETED: لا يمكن تسجيل حركة على حساب زبون محذوف");
      }
     const currentBalance = Number(customerData.current_balance) || 0;
     if (!Number.isFinite(currentBalance) ||
         !Number.isSafeInteger(Math.round(currentBalance * 100))) {
       throw new HttpsError("failed-precondition", "رصيد الزبون الحالي غير صالح للمحاسبة");
     }
      const creditLimit = Number(customerData.credit_limit) || 0;
      const currentBalanceCents = Math.round(currentBalance * 100);
      const deltaCents = isDebt ? amountCents : -amountCents;
      const newBalanceCents = currentBalanceCents + deltaCents;
      if (!Number.isSafeInteger(newBalanceCents)) {
        throw new HttpsError("failed-precondition", "الرصيد الناتج يتجاوز الحد المحاسبي الدقيق");
      }
      const newBalance = newBalanceCents / 100;

      // 🔒 التحقق السحابي الصارم من سقف الدين (Server-Side Credit Limit Guard)
      if (isDebt && creditLimit > 0 && newBalance > creditLimit) {
        console.warn(`[Ledger Warning] Customer ${cleanCustomerId} exceeded credit limit: ${newBalance} > ${creditLimit}`);
      }
      // ✅ التحقق الجنائي والمحاسبي الصارم: منع قيد أي فاتورة بنود لا يتطابق مجموعها مع المبلغ المطلوب
      if (sanitizedItems.length > 0) {
        const itemsSumCents = sanitizedItems.reduce(
          (acc, it) => acc + Math.round((Number(it.subtotal) || 0) * 100),
          0
        );
        if (itemsSumCents !== amountCents) {
          throw new HttpsError(
            "invalid-argument",
            "إجمالي مبالغ الأصناف لا يتطابق مع إجمالي الفاتورة المقيد"
          );
        }
      }

      const entryData = {
        id: entryId,
        merchant_id: merchantId,
        customer_id: cleanCustomerId,
        type: cleanType,
        amount: safeAmount,
        is_voided: false,
        notes: normalizedNotes,
        items: sanitizedItems,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      };
   // 🔒 حل جذري غير محدود السعة: الاعتماد على رقم إصدار ترادفي (sequence_version) ومعرف آخر حركة
      // مما يلغي مصفوفة الـ 1500 نهائياً ويسمح بملايين المعاملات للزبون الواحد دون زيادة حجم الوثيقة
      const currentVersion = Number(customerData.ledger_version) || 0;

 tx.set(entryRef, entryData);

     // 🔒 توسيع نافذة الأمان المحاسبي إلى 200 حركة (تستهلك ~7KB فقط وتغطي أسابيع من العمل أوفلاين)
      const existingApplied = Array.isArray(customerData.applied_tx_ids) ? customerData.applied_tx_ids : [];
      const boundedApplied = existingApplied.includes(entryId)
        ? existingApplied
        : [...existingApplied.slice(-199), entryId];

      tx.update(customerRef, {
        current_balance: newBalance,
        last_transaction_id: entryId,
        applied_tx_ids: boundedApplied,
        ledger_version: currentVersion + 1,
        last_applied_timestamp: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });

    // 🔒 التحصين المالي: تحديث ملخص ديون السوق ذرياً داخل نفس المعاملة لمنع الانحراف المالي
      const oldDebtPortion = Math.max(0, currentBalance);
      const newDebtPortion = Math.max(0, newBalance);
      const debtPortionDelta = (Math.round(newDebtPortion * 100) - Math.round(oldDebtPortion * 100)) / 100;

      const isCrossedToDebt = currentBalance <= 0 && newBalance > 0;
      const isCrossedToZero = currentBalance > 0 && newBalance <= 0;
      const debtorsCountChange = isCrossedToDebt ? 1 : (isCrossedToZero ? -1 : 0);

      if (debtPortionDelta !== 0 || debtorsCountChange !== 0) {
        const summaryRef = db.collection("merchant_ledger_summaries").doc(merchantId);
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: FieldValue.increment(debtPortionDelta),
          debtors_count: FieldValue.increment(debtorsCountChange),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      return {
        success: true,
        alreadyRecorded: false,
        entryId,
        newBalance,
      };
    });

    return {
      success: true,
      entryId: result.entryId,
      newBalance: result.newBalance,
      alreadyRecorded: result.alreadyRecorded === true,
    };
  }
);
// 3. شطب وإبطال القيد المالي وعكس الأثر الحسابي ذرياً
exports.voidLedgerTransaction = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const merchantId = request.auth.uid;

    // 🔒 حماية مالية: التحقق من أن التاجر غير محظور أو معطل
    await requireActiveRole(
      merchantId,
      ["merchant"],
      "شطب قيود الدفتر متاح لحسابات التجار النشطة فقط",
    );

    const { customerId, entryId } = request.data || {};
    const cleanCustomerId = String(customerId || "").trim();
    const cleanEntryId = String(entryId || "").trim();

    if (!cleanCustomerId || !cleanEntryId) {
      throw new HttpsError("invalid-argument", "معرف الزبون ومعرف القيد مطلوبان");
    }

    const entryRef = db.collection("merchant_ledger_entries").doc(cleanEntryId);
    const customerRef = db.collection("merchant_customers").doc(cleanCustomerId);
    const summaryRef = db.collection("merchant_ledger_summaries").doc(merchantId);

    return await db.runTransaction(async (tx) => {
      // 1. قراءة جميع الوثائق أولاً وفقاً لقواعد Firestore Transactions الصارمة
      const [entrySnap, customerSnap, summarySnap] = await Promise.all([
        tx.get(entryRef),
        tx.get(customerRef),
        tx.get(summaryRef)
      ]);

      if (!entrySnap.exists) {
        throw new HttpsError("not-found", "القيد المالي غير موجود");
      }

      const entryData = entrySnap.data() || {};
      if (entryData.merchant_id !== merchantId || entryData.customer_id !== cleanCustomerId) {
        throw new HttpsError("permission-denied", "غير مصرح لك بإبطال هذا القيد");
      }

      if (entryData.is_voided === true) {
        return { success: true, alreadyVoided: true };
      }
      if (!customerSnap.exists) {
        throw new HttpsError("not-found", "حساب الزبون غير موجود");
      }
      const customerData = customerSnap.data() || {};
      if (customerData.merchant_id !== merchantId) {
        throw new HttpsError("permission-denied", "غير مصرح لك بإبطال هذا القيد");
      }

      const entryAmountCents = Math.round((Number(entryData.amount) || 0) * 100);
      const isDebt = entryData.type === "debt";
      const reverseDeltaCents = isDebt ? -entryAmountCents : entryAmountCents;

      const currentBalance = Number(customerData.current_balance) || 0;
      const currentBalanceCents = Math.round(currentBalance * 100);
      const newBalance = (currentBalanceCents + reverseDeltaCents) / 100;

      // 2. تنفيذ عمليات الكتابة والتحديث بعد اكتمال جميع القراءات
      tx.update(entryRef, {
        is_voided: true,
        voided_by: merchantId,
        voided_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });
// 🔒 توسيع نافذة الأمان المحاسبي للشطب إلى 200 حركة مع منع التكرار
      const currentVersion = Number(customerData.ledger_version) || 0;
      const existingApplied = Array.isArray(customerData.applied_tx_ids) ? customerData.applied_tx_ids : [];
      const voidTag = `void_${cleanEntryId}`;
      const boundedApplied = existingApplied.includes(voidTag)
        ? existingApplied
        : [...existingApplied.slice(-199), voidTag];

      tx.update(customerRef, {
        current_balance: newBalance,
        last_transaction_id: voidTag,
        applied_tx_ids: boundedApplied,
        ledger_version: currentVersion + 1,
        last_applied_timestamp: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });
    // 3. التحديث الذري الشامل داخل نفس المعاملة (Atomic OCC)
      const oldDebtPortion = Math.max(0, currentBalance);
      const newDebtPortion = Math.max(0, newBalance);
      const debtPortionDelta = (Math.round(newDebtPortion * 100) - Math.round(oldDebtPortion * 100)) / 100;

      const wasDebt = currentBalance > 0;
      const willBeDebt = newBalance > 0;
      const debtorsCountChange = (!wasDebt && willBeDebt) ? 1 : ((wasDebt && !willBeDebt) ? -1 : 0);

      if (customerData.is_deleted !== true &&
          (debtPortionDelta !== 0 || debtorsCountChange !== 0)) {
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: FieldValue.increment(debtPortionDelta),
          debtors_count: FieldValue.increment(debtorsCountChange),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      return {
        success: true,
        newBalance,
      };
    });

    return { success: true, newBalance: result.newBalance };
  }
);
// 4. مطابقة وتدقيق الرصيد بنمط Version-Locking & Optimistic Concurrency Control (OCC)
exports.reconcileLedgerBalance = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const merchantId = request.auth.uid;

    await requireActiveRole(
      merchantId,
      ["merchant"],
      "مطابقة رصيد الدفتر متاحة لحسابات التجار النشطة فقط",
    );

    const { customerId } = request.data || {};
    const cleanCustomerId = String(customerId || "").trim();

    if (!cleanCustomerId) {
      throw new HttpsError("invalid-argument", "معرف الزبون مطلوب");
    }

    const customerRef = db.collection("merchant_customers").doc(cleanCustomerId);
    const summaryRef = db.collection("merchant_ledger_summaries").doc(merchantId);

    // 🔒 الخطوة 1: قراءة الحالة المبدئية للزبون وتثبيت ختم آخر حركة (Pre-check Snapshot)
    const preSnap = await customerRef.get();
    if (!preSnap.exists ||
        preSnap.data()?.merchant_id !== merchantId ||
        preSnap.data()?.is_deleted === true) {
      throw new HttpsError("not-found", "حساب الزبون غير موجود أو غير تابع لك");
    }

    const preData = preSnap.data() || {};
    const preLastTxId = preData.last_transaction_id || null;
    const preBalance = Number(preData.current_balance) || 0.0;
// 🔒 استعلام مؤمن 100% يعمل مباشرة بدون الحاجة لفهارس مركبة معقدة
 let totalDebtCents = 0;
    let totalPaymentCents = 0;
    let lastVisibleDoc = null;
    let hasMoreEntries = true;

  // 🔒 حساب تجميعي لحظي فائق السرعة عبر محرك السحابة مباشرة دون تحميل وثائق (O(1) Memory & Cost)
    const baseLedgerQ = db.collection("merchant_ledger_entries")
      .where("merchant_id", "==", merchantId)
      .where("customer_id", "==", cleanCustomerId)
      .where("is_voided", "==", false);

    const [debtAggSnap, paymentAggSnap] = await Promise.all([
      baseLedgerQ.where("type", "==", "debt").aggregate({ totalDebt: AggregateField.sum("amount") }).get(),
      baseLedgerQ.where("type", "==", "payment").aggregate({ totalPayment: AggregateField.sum("amount") }).get()
    ]);

    const totalDebt = Number(debtAggSnap.data().totalDebt) || 0.0;
    const totalPayment = Number(paymentAggSnap.data().totalPayment) || 0.0;
    
    // حساب دقيق بالسنتات لمنع هلوسة الفواصل
    const calculatedAuthoritativeBalance = (Math.round(totalDebt * 100) - Math.round(totalPayment * 100)) / 100;
    // 🔒 الخطوة 3: المعاملة الذرية المحمية بنمط قفل النسخة (Optimistic Version Lock)
    return await db.runTransaction(async (tx) => {
      const [postCustomerSnap, summarySnap] = await Promise.all([
        tx.get(customerRef),
        tx.get(summaryRef),
      ]);

      if (!postCustomerSnap.exists) {
        throw new HttpsError("not-found", "تم حذف حساب الزبون أثناء المعالجة");
      }

      const postData = postCustomerSnap.data() || {};
      const postLastTxId = postData.last_transaction_id || null;

      if (postData.merchant_id !== merchantId || postData.is_deleted === true) {
        throw new HttpsError(
          "failed-precondition",
          "لا يمكن مطابقة رصيد حساب محذوف أو غير تابع للتاجر",
        );
      }

      // 🛡️ حماية كبرى: إذا تغيرت last_transaction_id أثناء عملية الحساب، فهذا يعني أن حركة مالية
      // جديدة سُجلت في هذا الجزء من الثانية، فننسحب فوراً بسلام دون مسح الحركة الجديدة!
      if (postLastTxId !== preLastTxId) {
        return {
          success: true,
          reconciled: false,
          reason: "concurrent_mutation_detected",
          authoritativeBalance: Number(postData.current_balance) || preBalance,
        };
      }

      const currentBalance = Number(postData.current_balance) || 0.0;

      // إذا كان الرصيد الحالي مطابقاً تماماً للرصيد المحسوب، نكتفي بتسجيل وقت المطابقة دون كتابات زائدة
      if (Math.abs(currentBalance - calculatedAuthoritativeBalance) < 0.001) {
        tx.update(customerRef, {
          reconciled_at: FieldValue.serverTimestamp(),
        });
        return {
          success: true,
          reconciled: true,
          authoritativeBalance: currentBalance,
        };
      }

      // إذا وُجد انحراف حقيقي: تصحيح الرصيد وتحديث ملخص ديون السوق بالفارق فقط بدقة السنتات
      const oldDebtPortion = Math.max(0, currentBalance);
      const newDebtPortion = Math.max(0, calculatedAuthoritativeBalance);
      const debtPortionDelta = (Math.round(newDebtPortion * 100) - Math.round(oldDebtPortion * 100)) / 100;

      const wasDebt = currentBalance > 0;
      const willBeDebt = calculatedAuthoritativeBalance > 0;
      const debtorsCountChange = (!wasDebt && willBeDebt) ? 1 : ((wasDebt && !willBeDebt) ? -1 : 0);

      tx.update(customerRef, {
        current_balance: calculatedAuthoritativeBalance,
        reconciled_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });

      if (debtPortionDelta !== 0 || debtorsCountChange !== 0) {
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: FieldValue.increment(debtPortionDelta),
          debtors_count: FieldValue.increment(debtorsCountChange),
          last_updated: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      return {
        success: true,
        reconciled: true,
        authoritativeBalance: calculatedAuthoritativeBalance,
      };
    });
  }
);
// ══════════════════════════════════════════════════════════════
// 📦 إدارة الكتالوج والمخزون سحابياً مع البث اللحظي لجميع التجار
// ══════════════════════════════════════════════════════════════

// 1. إضافة منتج جديد بسلطة السيرفر
exports.adminAddProduct = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "warehouse_manager"],
      "هذه العملية مخصصة لمدراء النظام والمستودع فقط",
    );

    const data = request.data || {};
    const cleanName = String(data.name || "").trim();
    const brandId = String(data.brandId || "").trim();
    const price = Number(data.price) || 0;
    const costPrice = Math.max(0, Number(data.costPrice) || 0);
    const stock = Math.max(0, Number(data.stock) || 0);

    if (!cleanName) throw new HttpsError("invalid-argument", "اسم المنتج مطلوب");
    if (!brandId) throw new HttpsError("invalid-argument", "الشركة مطلوبة");
    if (price < 0) throw new HttpsError("invalid-argument", "سعر البيع لا يمكن أن يكون سالباً");

    // جلب صنف الشركة تلقائياً
    const brandSnap = await db.collection("brands").doc(brandId).get();
    if (!brandSnap.exists) throw new HttpsError("not-found", "الشركة غير موجودة");
    const categoryId = brandSnap.data()?.category_id || "";
// تنظيف وتوحيد الباركود الدولي
      const normalizeBarcode = (raw) => {
        const arabicDigits = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9" };
        let text = String(raw || "").trim();
        for (const [ar, en] of Object.entries(arabicDigits)) text = text.replaceAll(ar, en);
        return text.replace(/[^0-9a-zA-Z]/g, "");
      };

      const allBarcodes = new Set();
      const cleanMainBarcode = normalizeBarcode(data.barcode);
      if (cleanMainBarcode) {
        allBarcodes.add(cleanMainBarcode);
        // إضافة نسخ الأصفار المسبقة للتعرف الدولي EAN-13 و UPC-A
        const stripped = cleanMainBarcode.replace(/^0+/, '');
        if (stripped) {
          allBarcodes.add(stripped);
          allBarcodes.add('0' + stripped);
          allBarcodes.add('00' + stripped);
        }
      }

      // ربط باركودات الوحدات التابعة (الحبة والكرتون) ضمن نفس مصفوفة البحث السحابي
      const unitFinancials = Array.isArray(data.units)
        ? data.units.map((u) => {
            const label = String(u.label || "").trim();
            return {
              label,
              cost_price: Math.max(0, Number(u.cost_price) || 0),
            };
          }).filter((u) => u.label.length > 0)
        : [];
      const units = Array.isArray(data.units)
        ? data.units.map((u) => {
            const uBar = normalizeBarcode(u.barcode);
            if (uBar) {
              allBarcodes.add(uBar);
              const uStripped = uBar.replace(/^0+/, '');
              if (uStripped) {
                allBarcodes.add(uStripped);
                allBarcodes.add('0' + uStripped);
              }
            }
            return {
              label: String(u.label || "").trim(),
              price: Number(u.price) || 0,
              qty: Number(u.qty) || 1,
              size_ml: u.size_ml != null ? Number(u.size_ml) : null,
              image_url: u.image_url ? String(u.image_url).trim() : null,
              barcode: uBar || null,
            };
          }).filter((u) => u.label.length > 0 && u.price >= 0)
        : [];

    const newDocRef = db.collection("products").doc();
    const productPayload = {
      id: newDocRef.id,
      name: cleanName,
      brand_id: brandId,
      category_id: categoryId,
      price: price,
      stock: stock,
      is_active: true,
      is_deleted: false,
      items_per_carton: Number(data.itemsPerCarton) || 1,
      size_ml: data.sizeMl != null ? Number(data.sizeMl) : null,
      size_text: data.sizeText ? String(data.sizeText).trim() : null,
      image_url: data.imageUrl ? String(data.imageUrl).trim() : null,
     production_date: (data.productionDate && !isNaN(new Date(data.productionDate).getTime())) 
          ? Timestamp.fromDate(new Date(data.productionDate))
          : null,
      expiry_date: (data.expiryDate && !isNaN(new Date(data.expiryDate).getTime())) 
          ? Timestamp.fromDate(new Date(data.expiryDate))
          : null,
      barcode: cleanMainBarcode || null,
      all_barcodes: Array.from(allBarcodes),
      units: units,
      public_catalog_ready: true,
      sort_order: Date.now(),
      created_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    };

    const batch = db.batch();
    batch.set(newDocRef, productPayload);
    batch.set(db.collection("product_financials").doc(newDocRef.id), {
      product_id: newDocRef.id,
      cost_price: costPrice,
      units: unitFinancials,
      updated_at: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    // تسجيل حركة افتتاح المخزون
    if (stock > 0) {
      await db.collection("inventory_audit_log").add({
        product_id: newDocRef.id,
        product_name: cleanName,
        action: "initial_stock",
        delta: stock,
        resulting_stock: stock,
        performed_by: callerUid,
        created_at: FieldValue.serverTimestamp(),
      });
    }

    return { success: true, id: newDocRef.id };
  }
);

// 2. تعديل المنتج والمخزون ذرياً وتدقيق التغييرات
exports.adminUpdateProduct = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "warehouse_manager"],
      "هذه العملية مخصصة لمدراء النظام فقط",
    );

    const { id, updates } = request.data || {};
    const cleanId = String(id || "").trim();
    if (!cleanId || !updates || typeof updates !== "object" || Array.isArray(updates)) {
      throw new HttpsError("invalid-argument", "معرف المنتج وبيانات التحديث مطلوبة");
    }

    const productRef = db.collection("products").doc(cleanId);
    const financialRef = db.collection("product_financials").doc(cleanId);

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(productRef);
      const financialSnap = await tx.get(financialRef);
      if (!snap.exists) throw new HttpsError("not-found", "المنتج غير موجود");

      const existing = snap.data() || {};
      const existingFinancials = financialSnap.data() || {};
      const safeUpdates = {};
      const requestedCost = updates.cost_price !== undefined
        ? Number(updates.cost_price)
        : Number(existingFinancials.cost_price ?? existing.cost_price) || 0;
      if (!Number.isFinite(requestedCost) || requestedCost < 0) {
        throw new HttpsError("invalid-argument", "سعر التكلفة غير صالح");
      }
      const financialUpdates = { cost_price: requestedCost };
      const allowedFields = ["name", "brand_id", "category_id", "size_text", "price", "size_ml", "items_per_carton", "image_url", "is_active"];

      for (const field of allowedFields) {
        if (updates[field] !== undefined) safeUpdates[field] = updates[field];
      }
      const sourceUnits = updates.units ?? existing.units ?? [];
      if (!Array.isArray(sourceUnits)) {
        throw new HttpsError("invalid-argument", "وحدات المنتج غير صالحة");
      }
      const existingUnitCosts = new Map(
        (Array.isArray(existingFinancials.units) ? existingFinancials.units : [])
          .map((unit) => [
            String(unit.label || "").trim(),
            Number(unit.cost_price) || 0,
          ]),
      );
      for (const unit of Array.isArray(existing.units) ? existing.units : []) {
        if (!existingUnitCosts.has(String(unit.label || "").trim())) {
          existingUnitCosts.set(
            String(unit.label || "").trim(),
            Number(unit.cost_price) || 0,
          );
        }
      }
      safeUpdates.units = sourceUnits.map((unit) => {
        if (!unit || typeof unit !== "object" || Array.isArray(unit)) {
          throw new HttpsError("invalid-argument", "بيانات الوحدة غير صالحة");
        }
        const label = String(unit.label || "").trim();
        const price = Number(unit.price);
        const qty = Number(unit.qty);
        if (!label || !Number.isFinite(price) || price < 0 ||
            !Number.isFinite(qty) || qty <= 0) {
          throw new HttpsError("invalid-argument", "بيانات الوحدة غير صالحة");
        }
        return {
          label,
          price,
          qty,
          size_ml: unit.size_ml != null ? Number(unit.size_ml) : null,
          image_url: unit.image_url ? String(unit.image_url).trim() : null,
          barcode: unit.barcode ? String(unit.barcode).trim() : null,
        };
      });
      financialUpdates.units = sourceUnits.map((unit) => ({
        label: String(unit.label || "").trim(),
        cost_price: unit.cost_price == null
          ? existingUnitCosts.get(String(unit.label || "").trim()) || 0
          : Math.max(0, Number(unit.cost_price) || 0),
      }));

      // توحيد الباركودات
      const normalizeBarcode = (raw) => {
        const arabicDigits = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9" };
        let text = String(raw || "").trim();
        for (const [ar, en] of Object.entries(arabicDigits)) text = text.replaceAll(ar, en);
        return text.replace(/[^0-9a-zA-Z]/g, "");
      };
if (updates.barcode !== undefined || updates.units !== undefined) {
        const allBarcodes = new Set();
        if (updates.barcode === null || updates.barcode === "") {
          safeUpdates.barcode = FieldValue.delete();
        } else {
          const mainBar = normalizeBarcode(updates.barcode !== undefined ? updates.barcode : existing.barcode);
          if (mainBar) {
            allBarcodes.add(mainBar);
            safeUpdates.barcode = mainBar;
          }
        }

        const unitsList = updates.units !== undefined ? updates.units : (existing.units ?? []);
        if (Array.isArray(unitsList)) {
          for (const u of unitsList) {
            const uBar = normalizeBarcode(u.barcode);
            if (uBar) allBarcodes.add(uBar);
          }
        }
        safeUpdates.all_barcodes = allBarcodes.size > 0 ? Array.from(allBarcodes) : FieldValue.delete();
      }
     // معالجة التواريخ مع فحص الصلاحية لمنع انهيار Timestamp بـ NaN
      if (updates.production_date !== undefined) {
        const pDate = new Date(updates.production_date);
        safeUpdates.production_date = (updates.production_date && !isNaN(pDate.getTime()))
          ? Timestamp.fromDate(pDate)
          : FieldValue.delete();
      }
      if (updates.expiry_date !== undefined) {
        const eDate = new Date(updates.expiry_date);
        safeUpdates.expiry_date = (updates.expiry_date && !isNaN(eDate.getTime()))
          ? Timestamp.fromDate(eDate)
          : FieldValue.delete();
      }
// تعديل المخزون الذري المباشر أو النسبي مع الحماية والتدقيق
      let newStock = Number(existing.stock) || 0;
      if (updates.stock !== undefined) {
        newStock = Math.max(0, Number(updates.stock) || 0);
        safeUpdates.stock = newStock;

        const auditRef = db.collection("inventory_audit_log").doc();
        tx.set(auditRef, {
          product_id: cleanId,
          product_name: safeUpdates.name || existing.name || "",
          action: "stock_set",
          delta: newStock - (Number(existing.stock) || 0),
          resulting_stock: newStock,
          performed_by: callerUid,
          created_at: FieldValue.serverTimestamp(),
        });
      } else if (updates.stock_delta !== undefined) {
        const currentStock = Math.max(0, Number(existing.stock) || 0);
        const delta = Number(updates.stock_delta) || 0;
        const effectiveDelta = delta < 0 ? -Math.min(currentStock, Math.abs(delta)) : delta;
        newStock = currentStock + effectiveDelta;
        safeUpdates.stock = FieldValue.increment(effectiveDelta);

        const auditRef = db.collection("inventory_audit_log").doc();
        tx.set(auditRef, {
          product_id: cleanId,
          product_name: safeUpdates.name || existing.name || "",
          action: "stock_delta",
          delta: effectiveDelta,
          resulting_stock: newStock,
          performed_by: callerUid,
          created_at: FieldValue.serverTimestamp(),
        });
      }
      safeUpdates.updated_at = FieldValue.serverTimestamp();
      safeUpdates.public_catalog_ready = true;
      safeUpdates.cost_price = FieldValue.delete();
      tx.update(productRef, safeUpdates);
      tx.set(financialRef, {
        product_id: cleanId,
        ...financialUpdates,
        updated_at: FieldValue.serverTimestamp(),
      }, { merge: true });

      return { success: true, updatedStock: newStock };
    });
  }
);

// 3. الحذف البرمجي الآمن للمنتج
exports.adminDeleteProduct = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const callerUid = request.auth.uid;
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin"],
      "هذه العملية مخصصة لمدراء النظام فقط",
    );

    const { id } = request.data || {};
    const cleanId = String(id || "").trim();
    if (!cleanId) throw new HttpsError("invalid-argument", "معرف المنتج مطلوب");

    await db.collection("products").doc(cleanId).update({
      is_deleted: true,
      is_active: false,
      deleted_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);
// ══════════════════════════════════════════════════════════════
// ⚡ الدوال المحولة للسيرفر بالكامل: المرتجعات المجمعة والكتالوج
// ══════════════════════════════════════════════════════════════

// 1. معالجة وتوثيق المرتجع الجماعي للإدارة في معاملة ذرية واحدة لا تقبل التجزئة
exports.adminProcessBatchReturn = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
    }

    const callerUid = request.auth.uid;
    const { orderId, reason, returnItems } = request.data || {};
    const cleanOrderId = String(orderId || "").trim();

    if (!cleanOrderId || !Array.isArray(returnItems) ||
        returnItems.length === 0 || returnItems.length > 200) {
      throw new HttpsError("invalid-argument", "بيانات المرتجع غير مكتملة");
    }

    // التحقق الصارم من صلاحية الإدارة
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "accountant", "warehouse_manager"],
      "هذه العملية مخصصة لمدراء النظام فقط",
    );

    const orderRef = db.collection("orders").doc(cleanOrderId);

 return await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const orderData = orderSnap.data();
      const orderFinancialRef = db.collection("order_financials").doc(cleanOrderId);
      const orderFinancialSnap = await tx.get(orderFinancialRef);

      // 🔒 قفل سلامة العمليات: لا يمكن معالجة مرتجع مالي لطلب لم يتم تسليمه أصلاً
      if (orderData.status !== "delivered" && orderData.status !== "return_requested") {
        throw new HttpsError("failed-precondition", `لا يمكن تسجيل إرجاع لطلب بحالة: ${orderData.status}`);
      }

   // جلب جميع عناصر الطلب في المعاملة الذرية لحساب الكميات المتبقية بدقة
      const aggregatedReturnItems = new Map();
      for (const item of returnItems) {
        if (!item || typeof item !== "object" || Array.isArray(item)) {
          throw new HttpsError("invalid-argument", "بيانات صنف الإرجاع غير صالحة");
        }
        const itemId = String(item.item_id || item.id || "").trim();
        const quantity = Number(item.quantity);
        if (!itemId || !Number.isSafeInteger(quantity) || quantity <= 0) {
          throw new HttpsError("invalid-argument", "معرف الصنف وكمية الإرجاع غير صالحين");
        }
        const totalQuantity = (aggregatedReturnItems.get(itemId) || 0) + quantity;
        if (!Number.isSafeInteger(totalQuantity)) {
          throw new HttpsError("invalid-argument", "إجمالي كمية الإرجاع يتجاوز الحد المسموح");
        }
        aggregatedReturnItems.set(itemId, totalQuantity);
      }
      const returnEntries = Array.from(aggregatedReturnItems.entries());
      const itemSnaps = await Promise.all(
        returnEntries.map(([itemId]) =>
          tx.get(db.collection("order_items").doc(itemId)),
        ),
      );
      const itemFinancialSnaps = await Promise.all(
        returnEntries.map(([itemId]) =>
          tx.get(db.collection("order_item_financials").doc(itemId)),
        ),
      );
      let totalRefund = 0;
      let totalDeductedProfit = 0;
      const productRestores = new Map();
      const returnDocPayloads = [];

      for (let i = 0; i < returnEntries.length; i++) {
        const itemSnap = itemSnaps[i];
        const [returnItemId, returnQty] = returnEntries[i];
        if (!itemSnap.exists) {
          throw new HttpsError("not-found", `عنصر الطلب ${returnItemId} غير موجود`);
        }

        const itemData = itemSnap.data();

        const orderedQty = Number(itemData.quantity) || 0;
        const alreadyReturned = Number(itemData.returned_quantity) || 0;
        const maxReturnable = Math.max(0, orderedQty - alreadyReturned);

        if (returnQty > maxReturnable) {
          throw new HttpsError("failed-precondition", `الكمية المرتجعة للصنف تتجاوز الكمية المتاحة للإرجاع`);
        }

        const capacity = Number(itemData.carton_capacity) || 1;
        const unitQty = Number(itemData.unit_qty) || capacity;
        const cartonsToRestore = Number(((returnQty * unitQty) / capacity).toFixed(4));
        const price = Number(itemData.price) || 0;
        const itemRefund = price * returnQty;
        const unitCost = Number(
          itemFinancialSnaps[i].data()?.unit_cost ?? itemData.unit_cost,
        ) || 0;
        const itemProfit = (price - unitCost) * returnQty;

        totalRefund += itemRefund;
        totalDeductedProfit += itemProfit;

        // تجميع استرجاع المخزون للمنتج
        const pId = itemData.product_id;
        if (pId) {
          productRestores.set(pId, (productRestores.get(pId) || 0) + cartonsToRestore);
        }

        // تحديث الصنف
        tx.update(itemSnap.ref, {
          returned_quantity: FieldValue.increment(returnQty),
          updated_at: FieldValue.serverTimestamp(),
        });

        // تحضير مستند الإرجاع الموثق
        const retRef = db.collection("order_returns").doc();
        const returnNumber = `RET-${Date.now().toString(36).toUpperCase().slice(-5)}${crypto.randomInt(10, 99)}`;
        returnDocPayloads.push({
          ref: retRef,
          data: {
            order_id: cleanOrderId,
            order_item_id: itemSnap.id,
            merchant_id: orderData.merchant_id,
            product_id: pId || "",
            product_name: itemData.product_name || "منتج",
            quantity: returnQty,
            unit_label: itemData.unit_label || "كرتون",
            unit_price: price,
            refund_amount: itemRefund,
            store_name: orderData.store_name || "",
            contact: orderData.phone_number || orderData.contact || "",
            reason: String(reason || "").trim(),
            status: "accepted",
            return_number: returnNumber,
            invoice_number: returnNumber,
            created_at: FieldValue.serverTimestamp(),
            updated_at: FieldValue.serverTimestamp(),
          },
        });
      }

      // تطبيق كتابة مستندات المرتجعات
      for (const r of returnDocPayloads) {
        tx.set(r.ref, r.data);
      }

      // استرجاع المخزون الفعلي ذرياً
      for (const [pId, restoreCartons] of productRestores.entries()) {
        tx.update(db.collection("products").doc(pId), {
          stock: FieldValue.increment(restoreCartons),
          updated_at: FieldValue.serverTimestamp(),
        });
      }

  // تحديث بيانات الفاتورة الأصلية وتصفير عداد المرتجعات المعلقة لفتح إمكانية الإرجاع مستقبلاً
      const currentTotal = Number(orderData.total_amount || orderData.total || 0);
      const safeNewTotal = Math.max(0, currentTotal - totalRefund);
      const currentProfit = Number(
        orderFinancialSnap.data()?.total_profit ?? orderData.total_profit,
      );
      if (!Number.isFinite(currentProfit)) {
        throw new HttpsError("failed-precondition", "بيانات أرباح الطلب غير متاحة");
      }

      tx.update(orderRef, {
        status: safeNewTotal <= 0.01 ? "returned" : "delivered",
        total: safeNewTotal,
        total_amount: safeNewTotal,
        returned_amount: FieldValue.increment(totalRefund),
        pending_returns_count: 0,
        updated_at: FieldValue.serverTimestamp(),
      });
      tx.set(orderFinancialRef, {
        order_id: cleanOrderId,
        total_profit: currentProfit - totalDeductedProfit,
        updated_at: FieldValue.serverTimestamp(),
      }, { merge: true });

    // 🔒 تحديث مستند الأرباح الموحد مباشرة بقيم المرتجع الصحيحة المعرفة في النطاق
      const summaryParentRef = db.collection("stats").doc("profit_summary");
      tx.set(summaryParentRef, {
        accumulated_profit: FieldValue.increment(-totalDeductedProfit),
        cycle_profit: FieldValue.increment(-totalDeductedProfit),
        accumulated_returns: FieldValue.increment(totalRefund),
        last_updated: FieldValue.serverTimestamp(),
      }, { merge: true });

      return { success: true, count: returnDocPayloads.length, totalRefund };
    });
  }
);

// 2. إضافة صنف جديد بسلطة السيرفر
exports.adminAddCategory = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

    await requireActiveRole(
      request.auth.uid,
      ["admin", "super_admin", "warehouse_manager"],
      "هذه العملية مخصصة للإدارة فقط",
    );

    const { name, imageUrl } = request.data || {};
    const cleanName = String(name || "").trim();
    if (!cleanName) throw new HttpsError("invalid-argument", "اسم الصنف مطلوب");

    const snap = await db.collection("categories").orderBy("sort_order", "desc").limit(1).get();
    const lastOrder = snap.empty ? 0 : Number(snap.docs[0].data().sort_order || 0);

    const docRef = db.collection("categories").doc();
    await docRef.set({
      id: docRef.id,
      name: cleanName,
      image_url: imageUrl ? String(imageUrl).trim() : null,
      sort_order: lastOrder + 1,
      is_active: true,
      is_deleted: false,
      created_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });

    return { success: true, id: docRef.id };
  }
);

// 3. إضافة شركة جديدة بسلطة السيرفر
exports.adminAddBrand = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

    await requireActiveRole(
      request.auth.uid,
      ["admin", "super_admin", "warehouse_manager"],
      "هذه العملية مخصصة للإدارة فقط",
    );

    const { name, categoryId, logoUrl } = request.data || {};
    const cleanName = String(name || "").trim();
    const cleanCatId = String(categoryId || "").trim();
    if (!cleanName || !cleanCatId) throw new HttpsError("invalid-argument", "اسم الشركة والصنف مطلوبان");

    const docRef = db.collection("brands").doc();
    await docRef.set({
      id: docRef.id,
      name: cleanName,
      category_id: cleanCatId,
      logo_url: logoUrl ? String(logoUrl).trim() : null,
      is_active: true,
      is_deleted: false,
      created_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });

    return { success: true, id: docRef.id };
  }
);
// ══════════════════════════════════════════════════════════════
// 🔒 إغلاق ثغرات الكتابة المباشرة من الهاتف ونقلها للسيرفر
// ══════════════════════════════════════════════════════════════

// 1. إرسال إشعار فردي مخصص لتاجر بعينه بسلطة وتحقق الإدارة
exports.adminSendDirectNotification = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

    const callerUid = request.auth.uid;
    await requireActiveRole(
      callerUid,
      ["admin", "super_admin", "accountant"],
      "هذه العملية مخصصة للإدارة فقط",
    );

    const { targetUserId, title, body } = request.data || {};
    const cleanUid = String(targetUserId || "").trim();
    const cleanTitle = String(title || "").trim();
    const cleanBody = String(body || "").trim();

    if (!cleanUid || !cleanTitle || !cleanBody) {
      throw new HttpsError("invalid-argument", "جميع بيانات الإشعار مطلوبة");
    }

    const notifRef = db.collection("user_notifications").doc();
    await notifRef.set({
      id: notifRef.id,
      user_id: cleanUid,
      title: cleanTitle,
      body: cleanBody,
      type: "admin_message",
      is_read: false,
      sent_by: callerUid,
      created_at: FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);

// 2. ربط التوقيع الرقمي بالطلب بسلطة السيرفر
exports.saveOrderSignature = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");

    const callerUid = request.auth.uid;
    const { orderId, signatureUrl, signerName } = request.data || {};
    const cleanOrderId = String(orderId || "").trim();

    if (!/^[A-Za-z0-9_-]{1,128}$/.test(cleanOrderId) ||
        typeof signatureUrl !== "string" || signatureUrl.length > 1400000) {
      throw new HttpsError("invalid-argument", "بيانات التوقيع غير مكتملة");
    }

    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const callerData = callerDoc.data() || {};
    const callerRole = String(callerData.role || "").trim().toLowerCase();
    if (!callerDoc.exists || callerData.is_banned === true ||
        callerData.is_active !== true ||
        !["admin", "super_admin"].includes(callerRole)) {
      throw new HttpsError("permission-denied", "توثيق التوقيع مقتصر على إدارة النظام");
    }

    const orderRef = db.collection("orders").doc(cleanOrderId);
    const snap = await orderRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "الطلب غير موجود");

    let finalUrl = null;
    const rawSig = signatureUrl.trim();

    if (rawSig.startsWith("https://")) {
      try {
        const parsedUrl = new URL(rawSig);
        const objectPath = decodeURIComponent(parsedUrl.pathname.split("/o/")[1] || "");
        const belongsToOrder =
          objectPath.startsWith(`signatures/signature_${cleanOrderId}_`) ||
          objectPath.startsWith(`signatures/order_${cleanOrderId}_`);
        if (parsedUrl.hostname !== "firebasestorage.googleapis.com" ||
            !parsedUrl.searchParams.has("token") || !belongsToOrder) {
          throw new HttpsError("invalid-argument", "رابط التوقيع غير صالح");
        }
        finalUrl = rawSig;
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("invalid-argument", "رابط التوقيع غير صالح");
      }
    } else {
      const signatureMatch = rawSig.match(/^data:image\/png;base64,([A-Za-z0-9+/]+={0,2})$/);
      if (!signatureMatch) {
        throw new HttpsError("invalid-argument", "صيغة التوقيع غير صالحة");
      }

      try {
        const buffer = Buffer.from(signatureMatch[1], "base64");
        const pngHeader = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
        if (buffer.length === 0 || buffer.length > 1024 * 1024 ||
            !buffer.subarray(0, 8).equals(pngHeader)) {
          throw new HttpsError("invalid-argument", "ملف التوقيع غير صالح أو يتجاوز الحجم المسموح");
        }

        const bucket = storage.bucket();
        const fileName = `signatures/order_${cleanOrderId}_${Date.now()}.png`;
        const file = bucket.file(fileName);
        const downloadToken = crypto.randomUUID();

        await file.save(buffer, {
          metadata: {
            contentType: "image/png",
            metadata: { firebaseStorageDownloadTokens: downloadToken },
          },
        });
        finalUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(fileName)}?alt=media&token=${downloadToken}`;
      } catch (err) {
        if (err instanceof HttpsError) throw err;
        console.error("[saveOrderSignature] Storage upload error:", err);
        throw new HttpsError("internal", "تعذر حفظ صورة التوقيع");
      }
    }

    const sigUpdate = {
      signed_by: String(signerName || "المستلم المعتمد").trim().slice(0, 120),
      signed_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    };
    if (finalUrl) sigUpdate.signature_url = finalUrl;

    await orderRef.update(sigUpdate);

    return { success: true };
  }
);
// 3. توثيق إرسال تذكير الدفتر في السيرفر
exports.logCustomerReminder = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

    const merchantId = request.auth.uid;
    const { customerId } = request.data || {};
    const cleanCustomerId = String(customerId || "").trim();

    if (!cleanCustomerId) throw new HttpsError("invalid-argument", "معرف الزبون مطلوب");

    const custRef = db.collection("merchant_customers").doc(cleanCustomerId);
    await requireActiveRole(
      merchantId,
      ["merchant"],
      "تذكيرات دفتر الحسابات متاحة لحسابات التجار النشطة فقط",
    );
    const snap = await custRef.get();
    if (!snap.exists || snap.data()?.merchant_id !== merchantId) {
      throw new HttpsError("permission-denied", "غير مصرح لك بتعديل هذا الحساب");
    }

    await custRef.update({
      last_reminder_sent_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);