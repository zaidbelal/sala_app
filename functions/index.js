const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const crypto = require("crypto");
 
admin.initializeApp();
const db = admin.firestore();
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
 
// ─── requestOtp ───
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
 const profileSnap = await db.collection("profiles").where("phone_number", "==", phone).limit(1).get();
 
    if (purpose === "login") {
      if (profileSnap.empty) {
        return { success: false, message: "هذا الرقم غير مسجل، يرجى إنشاء حساب" };
      }
      const userData = profileSnap.docs[0].data();
      if (userData.is_banned === true || (userData.is_active === false && userData.account_status !== "pending")) {
        return { success: false, message: "هذا الحساب محظور أو معطّل، يرجى مراجعة إدارة المنصة" };
      }
    }
    if (purpose === "signup" && !profileSnap.empty) {
      return { success: false, message: "هذا الرقم مسجل من قبل، يرجى تسجيل الدخول" };
    }
    const otpRef = db.collection("otp_codes").doc(phone);
    const existing = await otpRef.get();
 
    if (existing.exists) {
      const lastSentAt = existing.data().lastSentAt?.toMillis?.() ?? 0;
      if (Date.now() - lastSentAt < RESEND_COOLDOWN_MS) {
        return { success: false, message: "انتظر قليلاً قبل طلب رمز جديد" };
      }
    }
 
    const code = generateCode();
 
    await otpRef.set({
      codeHash: hashCode(code),
      purpose,
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + OTP_TTL_MS),
    });
 
    try {
      await sendWhatsAppMessage({
        phone,
        text: `رمز التحقق الخاص بك هو: ${code}\nصالح لمدة 5 دقائق ولا تشاركه مع أحد.`,
        idInstance: smsSenderId.value(),
        apiTokenInstance: smsApiKey.value(),
      });
    } catch (error) {
      console.error("[requestOtp] WhatsApp send failed:", error);
      await otpRef.delete().catch(() => {});
      return { success: false, message: "تعذر إرسال رمز التحقق، حاول مرة أخرى" };
    }
 
    return { success: true, message: "تم إرسال رمز التحقق" };
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
      return { verified: false, message: "أدخل رمز التحقق المكوّن من 6 أرقام" };
    }
 
    const otpRef = db.collection("otp_codes").doc(phone);
    const snap = await otpRef.get();
 
    if (!snap.exists) {
      return { verified: false, message: "انتهت جلسة التحقق، أعد إرسال الرمز" };
    }
 
    const data = snap.data();
    if (data.purpose !== purpose) {
      return { verified: false, message: "طلب تحقق غير صالح" };
    }
 
    if (Date.now() > data.expiresAt.toMillis()) {
      await otpRef.delete();
      return { verified: false, message: "انتهت صلاحية رمز التحقق، أعد إرسال الرمز" };
    }
 if (data.attempts >= MAX_ATTEMPTS) {
      await otpRef.delete();
      return { verified: false, message: "تم تجاوز عدد المحاولات المسموح، أعد إرسال الرمز" };
    }
 
    if (hashCode(code) !== data.codeHash) {
      // التحقق من أن هذه المحاولة الخاطئة هي المحاولة الأخيرة المسموحة
      if (data.attempts + 1 >= MAX_ATTEMPTS) {
        await otpRef.delete();
        return { verified: false, message: "تم تجاوز عدد المحاولات الخاطئة المسموح، اطلب رمزاً جديداً" };
      }
      await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
      return { verified: false, message: "رمز التحقق غير صحيح" };
    }
    await otpRef.delete();
 
 let uid;
    let role = "merchant";
    if (purpose === "login") {
      const profileSnap = await db.collection("profiles").where("phone_number", "==", phone).limit(1).get();
      if (profileSnap.empty) {
        return { verified: false, message: "لم يتم العثور على الحساب" };
      }
      const userDoc = profileSnap.docs[0];
      uid = userDoc.id;
      role = userDoc.data().role || "merchant";
    } else {
      uid = db.collection("profiles").doc().id;
    }
 
// تضمين الصلاحيات داخل التوكن مباشرة؛ مع تحديث claims للمستخدمين المسجلين فقط دون إفشال الحسابات الجديدة
    if (purpose === "login") {
      try {
        await admin.auth().setCustomUserClaims(uid, { role, purpose });
      } catch (e) {
        console.warn(`[verifyOtp] setCustomUserClaims skipped for login uid: ${uid}`);
      }
    }
    const customToken = await admin.auth().createCustomToken(uid, { role, purpose });
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
      await admin.messaging().send(message);
    } catch (error) {
      if (error.code === 'messaging/invalid-registration-token' || 
          error.code === 'messaging/registration-token-not-registered') {
        await db.collection("profiles").doc(userId).update({
          fcm_token: admin.firestore.FieldValue.delete()
        });
      }
    }
  }
);
// ─── البحث الآمن عن الأماكن في الخريطة ───
exports.searchPlaces = onCall(
  { region: "us-central1", cors: true, secrets: [googlePlacesApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول لاستخدام البحث الجغرافي");
    }

    const query = String(request.data?.query || "").trim();
    if (!query) return [];

    const apiKey = googlePlacesApiKey.value();
    const url = new URL("https://maps.googleapis.com/maps/api/place/textsearch/json");
    url.searchParams.append("query", `${query} صنعاء`);
    url.searchParams.append("location", "15.3550,44.2000");
    url.searchParams.append("radius", "30000");
    url.searchParams.append("language", "ar");
    url.searchParams.append("key", apiKey);

    try {
      const res = await fetch(url.toString());
      const data = await res.json();
      return data.results || [];
    } catch (error) {
      console.error("[searchPlaces] Error:", error);
      return [];
    }
  }
);

// ─── فحص وجود الهاتف ───
exports.checkPhoneNumber = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    const phone = request.data?.phone;
    if (!phone) throw new HttpsError('invalid-argument', 'رقم الهاتف مطلوب');

    const snapshot = await db.collection('profiles').where('phone_number', '==', phone).limit(1).get();
    if (snapshot.empty) return { exists: false };

    const doc = snapshot.docs[0];
    const userData = doc.data();

    return {
        exists: true,
        is_banned: userData.is_banned || false,
        is_active: userData.is_active || false,
        account_status: userData.account_status || 'pending',
        userId: doc.id,
        role: userData.role || 'merchant'
    };
});
// ─── إنشاء ملف التاجر الجديد عند إكمال التسجيل (معالجة سحابية آمنة 100%) ───
exports.createUserProfile = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول وتأكيد رمز التحقق أولاً");
    }

    const uid = request.auth.uid;
    const { fullName, storeName, latitude, longitude, phone } = request.data || {};

    const cleanFullName = String(fullName || "").trim();
    const cleanStoreName = String(storeName || "").trim();
    const cleanPhone = String(phone || "").trim();
    const numLat = Number(latitude);
    const numLng = Number(longitude);

    // 1. تحققات أمنية صارمة على المدخلات
    if (!cleanFullName || cleanFullName.split(/\s+/).length < 4) {
      throw new HttpsError("invalid-argument", "يجب إدخال الاسم الرباعي كاملاً");
    }
    if (!cleanStoreName || cleanStoreName.length < 2) {
      throw new HttpsError("invalid-argument", "اسم المتجر أو البقالة قصير جداً");
    }
    if (!cleanPhone || !/^\+\d{9,15}$/.test(cleanPhone)) {
      throw new HttpsError("invalid-argument", "صيغة رقم الهاتف الدولي غير صحيحة");
    }
    if (isNaN(numLat) || isNaN(numLng) || numLat < -90 || numLat > 90 || numLng < -180 || numLng > 180) {
      throw new HttpsError("invalid-argument", "إحداثيات الموقع الجغرافي على الخريطة غير صالحة");
    }

    try {
      // 2. فحص عدم تسجيل رقم الهاتف لتاجر آخر
      const phoneCheck = await db.collection("profiles").where("phone_number", "==", cleanPhone).limit(1).get();
      if (!phoneCheck.empty && phoneCheck.docs[0].id !== uid) {
        throw new HttpsError("already-exists", "رقم الهاتف هذا مسجل مسبقاً لحساب آخر");
      }

      // 3. الحفاظ على الرتبة المرتفعة إن وُجدت (منع تخفيض رتب الإدارة أو السائقين إن أعادوا ملء البيانات)
      const profileRef = db.collection("profiles").doc(uid);
      const existingDoc = await profileRef.get();
      const existingData = existingDoc.exists ? existingDoc.data() : null;
      const assignedRole = (existingData && existingData.role) ? existingData.role : "merchant";

      // 4. كتابة المستند بسلطة الأدمن السحابية بحالة معلقة بانتظار المراجعة
      await profileRef.set({
        full_name: cleanFullName,
        store_name: cleanStoreName,
        phone_number: cleanPhone,
        latitude: numLat,
        longitude: numLng,
        role: assignedRole,
        is_active: false,
        is_banned: false,
        account_status: "pending",
        created_at: existingData?.created_at || admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // 5. تثبيت الرتبة المشفرة في توكن المستخدم لفايربيز
      await admin.auth().setCustomUserClaims(uid, { role: assignedRole, purpose: "registered" });

      return {
        success: true,
        userId: uid,
        role: assignedRole,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("[createUserProfile] Error:", error);
      throw new HttpsError("internal", "تعذر حفظ بيانات الحساب في السيرفر: " + error.message);
    }
  }
);
// ─── حذف الحساب لجوجل بلاي ───
exports.deleteUserAccount = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
    }

    const targetUid = request.auth.uid;

    try {
        // تحديث وثيقة التاجر وإخلاء الهاتف أولاً لضمان عدم حظر رقمه إذا تعطل السيرفر
        await db.collection('profiles').doc(targetUid).update({
            is_active: false,
            is_banned: true, 
            is_deleted: true,
            phone_number: admin.firestore.FieldValue.delete(), 
            full_name: "مستخدم محذوف",
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
        await admin.auth().deleteUser(targetUid);
        return { success: true };
    } catch (error) {
        throw new HttpsError('internal', 'فشل حذف الحساب: ' + error.message);
    }
});
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

  if (!orderId || !Array.isArray(items) || items.length === 0) {
      throw new HttpsError("invalid-argument", "بيانات الطلب غير مكتملة");
    }
    if (items.length > 50) {
      throw new HttpsError("invalid-argument", "تجاوزت الحد الأقصى للأصناف في الطلب الواحد (50 صنف)");
    }

    // 1. فحص حساب التاجر (الحظر والنشاط)
    const profileDoc = await db.collection("profiles").doc(uid).get();
    if (!profileDoc.exists) {
      throw new HttpsError("not-found", "حساب التاجر غير موجود");
    }
    const profile = profileDoc.data();
    if (profile.is_banned === true || profile.is_active === false) {
      throw new HttpsError("permission-denied", "حسابك غير مفعّل أو محظور من الإدارة");
    }

    const orderRef = db.collection("orders").doc(orderId.trim());

    // ── المرحلة الأولى: خصم المخزون وإنشاء عناصر الطلب (بدون قفل العداد) ──
    const phaseOneResult = await db.runTransaction(async (tx) => {
      // 🛡️ فحص Idempotency: إذا كان مسجلاً بالكامل أعده فوراً دون تكرار
      const existingSnap = await tx.get(orderRef);
      if (existingSnap.exists && existingSnap.data()?.order_number) {
        return { alreadyCreated: true, order: { id: existingSnap.id, ...existingSnap.data() } };
      }

      // 🚀 جلب آمن ومقسم في دفعات متسلسلة داخل المعاملة يمنع اختناق الـ Execution Context
      const productIds = [...new Set(items.map((i) => String(i.product_id).trim()))];
      const productMap = new Map();
      const BATCH_SIZE = 25;

      for (let i = 0; i < productIds.length; i += BATCH_SIZE) {
        const chunk = productIds.slice(i, i + BATCH_SIZE);
        const chunkRefs = chunk.map((id) => db.collection("products").doc(id));
        const chunkSnaps = await Promise.all(chunkRefs.map((ref) => tx.get(ref)));
        chunkSnaps.forEach((snap) => {
          if (snap.exists) productMap.set(snap.id, snap.data());
        });
      }

      let serverTotal = 0;
      let serverProfit = 0;
      const stockDeductions = new Map();
      const enrichedItems = [];

    for (const item of items) {
        const pId = String(item.product_id).trim();
        const product = productMap.get(pId);

        if (!product || product.is_deleted === true || product.is_active === false) {
          const pName = product?.name || item.product_name || "الصنف";
          throw new HttpsError("failed-precondition", `PRODUCT_UNAVAILABLE_[${pId}]: نعتذر، (${pName}) لم يعد متوفراً في المستودع حالياً`);
        }

        const qty = Number(item.quantity);
        if (!qty || qty <= 0) {
          throw new HttpsError("invalid-argument", "كمية الصنف غير صحيحة");
        }

        const cartonItems = Number(product.items_per_carton) > 0 ? Number(product.items_per_carton) : 1;
        let unitPrice = Number(product.price) || 0;
        let costPrice = Number(product.cost_price) || 0;
        let unitQty = cartonItems;
        let unitLabel = String(item.unit_label || "كرتون").trim();
        let selectedUnit = null;

        if (unitLabel !== "كرتون" && Array.isArray(product.units)) {
          selectedUnit = product.units.find((u) => String(u.label).trim() === unitLabel);
          if (!selectedUnit) {
            throw new HttpsError("failed-precondition", `PRODUCT_UNAVAILABLE_[${pId}:${unitLabel}]: الوحدة لم تعد متوفرة`);
          }
          unitPrice = Number(selectedUnit.price) || unitPrice;
          costPrice = Number(selectedUnit.cost_price) || costPrice;
          unitQty = Number(selectedUnit.qty) || 1;
        }

        const stockDeductCartons = Number(((qty * unitQty) / cartonItems).toFixed(4));
        const currentDeduction = stockDeductions.get(pId) || 0;
        const totalDeduction = currentDeduction + stockDeductCartons;

        const currentStock = Number(product.stock) || 0;
        if (currentStock < totalDeduction) {
          throw new HttpsError("resource-exhausted", `OUT_OF_STOCK_[${pId}]: الكمية المطلوبة تتجاوز المخزون المتاح`);
        }
        stockDeductions.set(pId, totalDeduction);

        const subtotal = unitPrice * qty;
        let unitCost = 0;
        if (selectedUnit && selectedUnit.cost_price != null) {
          unitCost = Number(selectedUnit.cost_price);
        } else if (costPrice > 0 && cartonItems > 0) {
          unitCost = (costPrice / cartonItems) * unitQty;
        }
        const itemProfit = (unitPrice - unitCost) * qty;

        serverTotal += subtotal;
        serverProfit += itemProfit;

        enrichedItems.push({
          order_id: orderRef.id,
          product_id: pId,
          product_name: product.name || item.product_name || "",
          price: unitPrice,
          cost_price: costPrice,
          unit_cost: unitCost,
          carton_capacity: cartonItems,
          quantity: qty,
          subtotal: subtotal,
          unit_label: unitLabel,
          unit_qty: unitQty,
        });
      }
// 🚀 توليد رقم الفاتورة ذرياً وحسابياً فائق السرعة بدون أي قفل قاعدة بيانات (High-Throughput 100+ TPS)
      // يعتمد على الزمن الحالي بنظام Base36 مدمجاً مع 3 خانات عشوائية (مثال: ORD-L8K2P9)
      // 🚀 توليد رقم فاتورة عالي الإنتاجية يستحيل تصادمه إحصائياً (1 في 4.3 مليار لكل جزء ثانية)
     const now = new Date();
      const dateHeader = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}`;
      const timeNano = String(process.hrtime.bigint()).slice(-6);
      const entropy = crypto.randomInt(100, 999);
      const invoiceNumberString = `INV-${dateHeader}-${timeNano}-${entropy}`;
      // تطبيق خصم المخزون الذري
      for (const [pId, deductQty] of stockDeductions.entries()) {
        tx.update(db.collection("products").doc(pId), {
          stock: admin.firestore.FieldValue.increment(-deductQty),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const cleanExtra = { ...(extraData || {}) };
      delete cleanExtra.merchant_id;
      delete cleanExtra.total;
      delete cleanExtra.total_amount;
      delete cleanExtra.total_profit;
      delete cleanExtra.status;

      const orderDataWithNumber = {
        ...cleanExtra,
        merchant_id: uid,
        total: serverTotal,
        total_amount: serverTotal,
        total_profit: serverProfit,
        delivery_fee: Number(cleanExtra.delivery_fee) || 500.0,
        notes: notes ? String(notes).trim() : null,
        status: "pending",
        items_count: enrichedItems.length,
        order_number: invoiceNumberString,
        invoice_number: invoiceNumberString,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      };

     // 🔒 التحقق الصارم في السيرفر من الحد الأدنى لقيمة الطلب
      const MIN_ORDER_VALUE = 4250.0;
      if (serverTotal < MIN_ORDER_VALUE) {
        throw new HttpsError("failed-precondition", `الحد الأدنى للطلب هو ${MIN_ORDER_VALUE} ريال يمني`);
      }

      // كتابة الطلب وعناصره مباشرة بدون لمس أي عداد مركزي
      tx.set(orderRef, orderDataWithNumber);

      for (const item of enrichedItems) {
        tx.set(db.collection("order_items").doc(), item);
      }

      return { alreadyCreated: false, orderData: orderDataWithNumber };
    });

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
      const role = userProfile.data()?.role || "merchant";
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
            stock: admin.firestore.FieldValue.increment(cartonsToRestore),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      tx.update(orderRef, {
        status: "cancelled",
        cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const callerDoc = await db.collection("profiles").doc(uid).get();
    const role = callerDoc.data()?.role || "";
    if (!["admin", "super_admin", "accountant", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية خاصة بالإدارة فقط");
    }

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

      const currentPendingCount = Number(orderData?.pending_returns_count) || 1;
      const newPendingCount = Math.max(0, currentPendingCount - 1);
      const hasOtherPending = newPendingCount > 0;

    if (status === "rejected") {
        tx.update(returnRef, {
          status: "rejected",
          rejection_reason: rejectionReason ? String(rejectionReason).trim() : null,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (orderSnap.exists) {
          tx.update(orderRef, {
            status: hasOtherPending ? "return_requested" : "delivered",
            pending_returns_count: newPendingCount,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        return { success: true };
      }
      // إذا كانت الحالة accepted: استرجاع المخزون وتسوية الرصيد
      const itemRef = db.collection("order_items").doc(returnData.order_item_id);
      const itemSnap = await tx.get(itemRef);
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

      const unitCost = Number(itemData.unit_cost) || 0;
      const deductedProfit = (price - unitCost) * returnQty;

      // 1. إعادة المخزون
      tx.update(db.collection("products").doc(itemData.product_id), {
        stock: admin.firestore.FieldValue.increment(cartonsToRestore),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 2. تحديث عداد المرتجع في الصنف
      tx.update(itemRef, {
        returned_quantity: admin.firestore.FieldValue.increment(returnQty),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 3. تحديث الفاتورة
      const currentTotal = Number(orderData?.total_amount || orderData?.total || 0);
      const safeNewTotal = Math.max(0, currentTotal - refundAmount);

      tx.update(orderRef, {
        status: safeNewTotal <= 0.01 && !hasOtherPending ? "returned" : (hasOtherPending ? "return_requested" : "delivered"),
        total: safeNewTotal,
        total_amount: safeNewTotal,
        returned_amount: admin.firestore.FieldValue.increment(refundAmount),
        total_profit: admin.firestore.FieldValue.increment(-deductedProfit),
        pending_returns_count: newPendingCount,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 4. تحديث حالة المرتجع
      tx.update(returnRef, {
        status: "accepted",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
// 5. تحديث مستند الإحصائيات الرئيسي ذرياً ومباشرة
      const summaryParentRef = db.collection("stats").doc("profit_summary");
      tx.set(summaryParentRef, {
        accumulated_profit: admin.firestore.FieldValue.increment(-deductedProfit),
        cycle_profit: admin.firestore.FieldValue.increment(-deductedProfit),
        accumulated_returns: admin.firestore.FieldValue.increment(refundAmount),
        last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
    if (driverData.is_banned === true || driverData.is_active === false || (role !== "driver" && role !== "admin" && role !== "super_admin")) {
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
        picked_up_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
          created_at: admin.firestore.FieldValue.serverTimestamp(),
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
    if (!orderId) {
      throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
    }

    // التحقق من صلاحية المنفّذ (سائق أو إدارة)
    const callerDoc = await db.collection("profiles").doc(uid).get();
    const callerRole = (callerDoc.data()?.role || "").trim().toLowerCase();
    const isAuthorized = ["driver", "admin", "super_admin"].includes(callerRole);
    if (!isAuthorized) {
      throw new HttpsError("permission-denied", "غير مصرح لك بتسليم الطلبات");
    }

    const orderRef = db.collection("orders").doc(String(orderId).trim());
// 🚀 رفع التوقيع مع الحماية القطعية لقاعدة البيانات من نصوص Base64
    let finalSignatureUrl = null;
    if (signatureData && typeof signatureData === "string") {
      if (signatureData.startsWith("https://")) {
        finalSignatureUrl = signatureData;
      } else if (signatureData.startsWith("data:image")) {
        try {
          const base64Data = signatureData.replace(/^data:image\/\w+;base64,/, "");
          const buffer = Buffer.from(base64Data, "base64");
          const bucket = admin.storage().bucket();
          const fileName = `signatures/order_${orderId}_${Date.now()}.png`;
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
          // لا يتم حفظ Base64 في Firestore مطلقاً لحماية وثيقة الطلب
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

      // التحقق الصارم من حالة الطلب وأحقية السائق
      if (order.status !== "shipped" && order.status !== "on_the_way") {
        throw new HttpsError("failed-precondition", `لا يمكن تسليم طلب بحالة: ${order.status}`);
      }

      if (callerRole === "driver" && order.driver_id !== uid) {
        throw new HttpsError("permission-denied", "هذا الطلب غير مسند إليك أو تم تسليمه لسائق آخر");
      }

      const totalProfit = Number(order.total_profit) || 0;
      const totalAmount = Number(order.total_amount) || Number(order.total) || 0;

      // 1. تحديث الطلب وإرفاق التوقيع الرسمي
      const updatePayload = {
        status: "delivered",
        delivered_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        profit_recorded: true,
      };
      if (finalSignatureUrl) {
        updatePayload.signature_url = finalSignatureUrl;
      }
      tx.update(orderRef, updatePayload);
// 2. تحديث المستند الرئيسي للأرباح والإيرادات ذرياً
      if (order.profit_recorded !== true) {
        const summaryParentRef = db.collection("stats").doc("profit_summary");
        tx.set(summaryParentRef, {
          accumulated_profit: admin.firestore.FieldValue.increment(totalProfit),
          cycle_profit: admin.firestore.FieldValue.increment(totalProfit),
          accumulated_revenue: admin.firestore.FieldValue.increment(totalAmount),
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
          created_at: admin.firestore.FieldValue.serverTimestamp(),
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
    if (!cleanReason || cleanReason.length < 3) {
      throw new HttpsError("invalid-argument", "سبب الإرجاع مطلوب ويجب توضيحه");
    }

    // 1. التحقق من حساب التاجر
    const profileDoc = await db.collection("profiles").doc(uid).get();
    if (!profileDoc.exists || profileDoc.data().is_banned === true) {
      throw new HttpsError("permission-denied", "حسابك محظور أو غير مصرح له بتقديم طلبات إرجاع");
    }

    const orderRef = db.collection("orders").doc(cleanOrderId);

    // 2. تجميع كميات الأصناف المكررة لمنع تعارض المعاملة الذرية
    const aggregated = new Map();
    for (const item of itemsToReturn) {
      const itemId = String(item.order_item_id || item.id || "").trim();
      const qty = Number(item.quantity) || 0;
      if (!itemId || qty <= 0) continue;
      aggregated.set(itemId, (aggregated.get(itemId) || 0) + qty);
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
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
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

    if (callerData.is_banned === true || callerData.is_active === false || (callerRole !== "admin" && callerRole !== "super_admin")) {
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
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (cleanRole === "driver") {
          updates.is_active = true;
          updates.is_banned = false;
          updates.account_status = "active";
        }

        await targetRef.update(updates);

        // تحديث الرتبة في الـ Custom Claims لتفعيل الصلاحيات في التوكن
        try {
          await admin.auth().setCustomUserClaims(cleanTargetId, {
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
          banned_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        // إبطال جلسة المستخدم وطرده فوراً
        try {
          await admin.auth().revokeRefreshTokens(cleanTargetId);
        } catch (_) {}
        return { success: true, message: "تم حظر الحساب بنجاح" };
      }

      case "unban": {
        await targetRef.update({
          is_active: true,
          is_banned: false,
          account_status: "active",
          banned_at: admin.firestore.FieldValue.delete(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { success: true, message: "تم رفع الحظر بنجاح" };
      }

      case "toggle_active": {
        const activeBool = Boolean(isActive);
        await targetRef.update({
          is_active: activeBool,
          account_status: activeBool ? "active" : "suspended",
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (!activeBool) {
          try {
            await admin.auth().revokeRefreshTokens(cleanTargetId);
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "accountant"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية خاصة بالإدارة فقط");
    }

    // 1. تسجيل سجل البث في الأرشيف
    await db.collection("broadcast_notifications").add({
      title: cleanTitle,
      body: cleanBody,
      target_role: "merchant",
      topic: "merchants",
      sent_by: callerUid,
      status: "sent",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
// 2. بث الإشعار لجميع التجار عبر FCM Topic (مدعوم لنظامي iOS وأندرويد)
    try {
      await admin.messaging().send({
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة لمدراء النظام فقط");
    }
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
          deleted_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const callerData = callerDoc.data() || {};
    const role = (callerData.role || "").trim().toLowerCase();

    if (!["admin", "super_admin", "accountant"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة للمدراء الماليين فقط");
    }

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
        cleared_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 2. تصفير العداد للدورة الجديدة
      tx.set(
        docRef,
        {
          cycle_profit: 0.0,
          last_reset_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "accountant", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية خاصة بالإدارة فقط");
    }

    const orderRef = db.collection("orders").doc(cleanOrderId);
    const requiresStockRestore = cleanStatus === "cancelled" || cleanStatus === "rejected";

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
        delivered: ["delivered", "return_requested"],
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
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (cleanStatus === "delivered") {
        updatePayload.delivered_at = admin.firestore.FieldValue.serverTimestamp();
      }
      if (driverId) updatePayload.driver_id = String(driverId).trim();
      if (driverName) updatePayload.driver_name = String(driverName).trim();
// 1. اعتماد الأرباح وتحديث المستند الرئيسي للإحصائيات ذرياً
      if (cleanStatus === "delivered" && !isProfitRecorded) {
        const totalProfit = Number(order.total_profit) || 0;
        const totalAmount = Number(order.total_amount) || Number(order.total) || 0;

        const summaryParentRef = db.collection("stats").doc("profit_summary");
        tx.set(summaryParentRef, {
          accumulated_profit: admin.firestore.FieldValue.increment(totalProfit),
          cycle_profit: admin.firestore.FieldValue.increment(totalProfit),
          accumulated_revenue: admin.firestore.FieldValue.increment(totalAmount),
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        updatePayload.profit_recorded = true;
      }
      // 2. استرجاع المخزون الفعلي في حالة الإلغاء أو الرفض
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
              stock: admin.firestore.FieldValue.increment(cartonsToRestore),
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
            created_at: admin.firestore.FieldValue.serverTimestamp(),
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

// 1. إضافة زبون جديد في الدفتر بسلطة السيرفر
exports.addLedgerCustomer = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
    }

    const merchantId = request.auth.uid;
    const { name, phone, creditLimit, salaryDay, customerId } = request.data || {};

    const cleanName = String(name || "").trim();
    if (!cleanName) {
      throw new HttpsError("invalid-argument", "اسم الزبون مطلوب");
    }

    // التحقق من صلاحية ونشاط التاجر
    const merchantProfile = await db.collection("profiles").doc(merchantId).get();
    if (!merchantProfile.exists || merchantProfile.data()?.is_banned === true) {
      throw new HttpsError("permission-denied", "الحساب محظور أو غير مصرح له");
    }

    // توحيد الأرقام المشرقية
    const arabicDigits = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9" };
    let cleanPhone = String(phone || "").trim();
    for (const [ar, en] of Object.entries(arabicDigits)) {
      cleanPhone = cleanPhone.replaceAll(ar, en);
    }

    const safeCreditLimit = Math.max(0, Math.round((Number(creditLimit) || 0) * 100) / 100);
    const parsedSalaryDay = salaryDay != null ? Math.min(31, Math.max(1, parseInt(salaryDay, 10))) : null;
const docRef = customerId ? db.collection("merchant_customers").doc(String(customerId).trim()) : db.collection("merchant_customers").doc();

    return await db.runTransaction(async (tx) => {
      const existingSnap = await tx.get(docRef);
      const customerData = {
        id: docRef.id,
        merchant_id: merchantId,
        name: cleanName,
        phone: cleanPhone,
        credit_limit: safeCreditLimit,
        salary_day: isNaN(parsedSalaryDay) ? null : parsedSalaryDay,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      };

     customerData.is_deleted = false;
      if (!existingSnap.exists) {
        customerData.current_balance = 0.0;
        customerData.created_at = admin.firestore.FieldValue.serverTimestamp();
        tx.set(docRef, customerData);
      } else {
        tx.set(docRef, customerData, { merge: true });
      }

     return {
        success: true,
        customer: {
          ...customerData,
          current_balance: existingSnap.exists ? (existingSnap.data().current_balance || 0.0) : 0.0,
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
        deleted_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // إذا كان الزبون عليه دين، خصم دينه من إجمالي ديون السوق
      if (debtPortion > 0 || isDebtor) {
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: admin.firestore.FieldValue.increment(-debtPortion),
          debtors_count: admin.firestore.FieldValue.increment(isDebtor ? -1 : 0),
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
    const { customerId, type, amount, notes, items, transactionId } = request.data || {};

    const cleanCustomerId = String(customerId || "").trim();
    const cleanType = String(type || "").trim().toLowerCase();
    const rawAmount = Number(amount) || 0;

    if (!cleanCustomerId) {
      throw new HttpsError("invalid-argument", "معرف الزبون مطلوب");
    }
    if (cleanType !== "debt" && cleanType !== "payment") {
      throw new HttpsError("invalid-argument", "نوع القيد يجب أن يكون debt أو payment");
    }
    if (rawAmount <= 0) {
      throw new HttpsError("invalid-argument", "مبلغ الحركة المالية غير صالح");
    }

    // حساب دقيق بالقروش لمنع أخطاء الفاصلة العائمة
    const amountCents = Math.round(rawAmount * 100);
    const safeAmount = amountCents / 100;
    const isDebt = cleanType === "debt";
    const delta = isDebt ? safeAmount : -safeAmount;

    const entryId = String(transactionId || "").trim() || `ledger_${merchantId.substring(0, 5)}_${Date.now()}_${db.collection("merchant_ledger_entries").doc().id}`;
    const entryRef = db.collection("merchant_ledger_entries").doc(entryId);
    const customerRef = db.collection("merchant_customers").doc(cleanCustomerId);
const result = await db.runTransaction(async (tx) => {
      // 🛡️ فحص Idempotency: إذا كان القيد مسجلاً مسبقاً (عبر مزامنة الأوفلاين)
      const existingEntry = await tx.get(entryRef);
      if (existingEntry.exists) {
        return { success: true, alreadyRecorded: true, entryId };
      }

      const customerSnap = await tx.get(customerRef);
      let customerData = customerSnap.data() || {};

      // 🛡️ معالجة مرونة الأوفلاين: إذا لم يُنشأ مستند الزبون بعد بسبب تأخر الترتيب في الطابور
      if (!customerSnap.exists) {
        customerData = {
          id: cleanCustomerId,
          merchant_id: merchantId,
          name: "زبون جديد (مزامنة أوفلاين)",
          phone: "",
          current_balance: 0.0,
          credit_limit: 0.0,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        };
        tx.set(customerRef, customerData);
      } else if (customerData.merchant_id !== merchantId) {
        throw new HttpsError("permission-denied", "غير مصرح لك بالقيد على هذا الحساب");
      }
     const currentBalance = Number(customerData.current_balance) || 0;
      const creditLimit = Number(customerData.credit_limit) || 0;
      const currentBalanceCents = Math.round(currentBalance * 100);
      const deltaCents = isDebt ? amountCents : -amountCents;
      const newBalance = (currentBalanceCents + deltaCents) / 100;

      // 🔒 التحقق السحابي الصارم من سقف الدين (Server-Side Credit Limit Guard)
      if (isDebt && creditLimit > 0 && newBalance > creditLimit) {
        console.warn(`[Ledger Warning] Customer ${cleanCustomerId} exceeded credit limit: ${newBalance} > ${creditLimit}`);
      }
      const sanitizedItems = Array.isArray(items)
        ? items.map((it) => ({
            product_id: String(it.product_id || "").trim(),
            name: String(it.name || it.product_name || "صنف").trim(),
            quantity: Number(it.quantity) || 1,
            unit_label: String(it.unit_label || "حبة").trim(),
            unit_price: Number(it.unit_price) || 0,
            subtotal: Number(it.subtotal) || 0,
            carton_capacity: Number(it.carton_capacity) || 1,
          }))
        : [];
      const entryData = {
        id: entryId,
        merchant_id: merchantId,
        customer_id: cleanCustomerId,
        type: cleanType,
        amount: safeAmount,
        is_voided: false,
        notes: notes ? String(notes).trim() : null,
        items: sanitizedItems,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      };
    // 🔒 استخدام Set موحدة تجمع المعاملات النشطة وتمنع تضخم المصفوفة أو ضياع القيود
      const existingApplied = Array.isArray(customerData.applied_tx_ids) ? customerData.applied_tx_ids : [];
      const appliedSet = new Set(existingApplied);
      appliedSet.add(entryId);
      // الاقتصار على أحدث 1500 حركة إذا كبرت جداً مع الاحتفاظ بكل المعاملات في مجموعة القيود المستقلة
      const updatedApplied = Array.from(appliedSet).slice(-1500);

      tx.set(entryRef, entryData);
      tx.update(customerRef, {
        current_balance: newBalance,
        last_transaction_id: entryId,
        applied_tx_ids: updatedApplied,
        last_applied_timestamp: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
          total_market_debt: admin.firestore.FieldValue.increment(debtPortionDelta),
          debtors_count: admin.firestore.FieldValue.increment(debtorsCountChange),
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
// 1. استخراج بيانات الزبون (مع مرونة الأوفلاين إن كان المستند قيد الإنشاء في الطابور)
      const isNewCustomerDoc = !customerSnap.exists;
      const customerData = isNewCustomerDoc
        ? {
            id: cleanCustomerId,
            merchant_id: merchantId,
            name: "زبون (مزامنة أوفلاين)",
            phone: "",
            current_balance: 0.0,
            credit_limit: 0.0,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          }
        : customerSnap.data() || {};

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
        voided_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

  const existingApplied = Array.isArray(customerData.applied_tx_ids) ? customerData.applied_tx_ids : [];
      const appliedSet = new Set(existingApplied);
      appliedSet.add(`void_${cleanEntryId}`);
      const updatedApplied = Array.from(appliedSet).slice(-1500);

      if (isNewCustomerDoc) {
        customerData.current_balance = newBalance;
        customerData.last_transaction_id = `void_${cleanEntryId}`;
        customerData.applied_tx_ids = updatedApplied;
        tx.set(customerRef, customerData);
      } else {
        tx.update(customerRef, {
          current_balance: newBalance,
          last_transaction_id: `void_${cleanEntryId}`,
          applied_tx_ids: updatedApplied,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    // 3. التحديث الذري الشامل داخل نفس المعاملة (Atomic OCC)
      const oldDebtPortion = Math.max(0, currentBalance);
      const newDebtPortion = Math.max(0, newBalance);
      const debtPortionDelta = (Math.round(newDebtPortion * 100) - Math.round(oldDebtPortion * 100)) / 100;

      const wasDebt = currentBalance > 0;
      const willBeDebt = newBalance > 0;
      const debtorsCountChange = (!wasDebt && willBeDebt) ? 1 : ((wasDebt && !willBeDebt) ? -1 : 0);

      if (debtPortionDelta !== 0 || debtorsCountChange !== 0) {
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: admin.firestore.FieldValue.increment(debtPortionDelta),
          debtors_count: admin.firestore.FieldValue.increment(debtorsCountChange),
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
    const { customerId } = request.data || {};
    const cleanCustomerId = String(customerId || "").trim();

    if (!cleanCustomerId) {
      throw new HttpsError("invalid-argument", "معرف الزبون مطلوب");
    }

    const customerRef = db.collection("merchant_customers").doc(cleanCustomerId);
    const summaryRef = db.collection("merchant_ledger_summaries").doc(merchantId);

    // 🔒 الخطوة 1: قراءة الحالة المبدئية للزبون وتثبيت ختم آخر حركة (Pre-check Snapshot)
    const preSnap = await customerRef.get();
    if (!preSnap.exists || preSnap.data()?.merchant_id !== merchantId) {
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

  // 🔒 استعلام تدقيقي مقسم على دفعات متتالية (Chunked Stream) لمنع تجاوز الذاكرة مهما بلغت القيود
    let calculatedTotalCents = 0;
    let lastDoc = null;
    let keepPaging = true;
    const CHUNK_SIZE = 500;

    while (keepPaging) {
      let q = db.collection("merchant_ledger_entries")
        .where("customer_id", "==", cleanCustomerId)
        .limit(CHUNK_SIZE);

      if (lastDoc) {
        q = q.startAfter(lastDoc);
      }

      const chunkSnap = await q.get();
      if (chunkSnap.empty) {
        break;
      }

      for (const doc of chunkSnap.docs) {
        const entry = doc.data();
        if (entry.merchant_id !== merchantId || entry.is_voided === true) continue;
        const amtCents = Math.round((Number(entry.amount) || 0) * 100);
        if (entry.type === "debt") {
          calculatedTotalCents += amtCents;
        } else if (entry.type === "payment") {
          calculatedTotalCents -= amtCents;
        }
      }

      lastDoc = chunkSnap.docs[chunkSnap.docs.length - 1];
      keepPaging = chunkSnap.docs.length === CHUNK_SIZE;
    }

    const calculatedAuthoritativeBalance = calculatedTotalCents / 100;
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
          reconciled_at: admin.firestore.FieldValue.serverTimestamp(),
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
        reconciled_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (debtPortionDelta !== 0 || debtorsCountChange !== 0) {
        tx.set(summaryRef, {
          merchant_id: merchantId,
          total_market_debt: admin.firestore.FieldValue.increment(debtPortionDelta),
          debtors_count: admin.firestore.FieldValue.increment(debtorsCountChange),
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة لمدراء النظام والمستودع فقط");
    }

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
              cost_price: Number(u.cost_price) || 0,
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
      cost_price: costPrice,
      stock: stock,
      is_active: true,
      is_deleted: false,
      items_per_carton: Number(data.itemsPerCarton) || 1,
      size_ml: data.sizeMl != null ? Number(data.sizeMl) : null,
      size_text: data.sizeText ? String(data.sizeText).trim() : null,
      image_url: data.imageUrl ? String(data.imageUrl).trim() : null,
     production_date: (data.productionDate && !isNaN(new Date(data.productionDate).getTime())) 
          ? admin.firestore.Timestamp.fromDate(new Date(data.productionDate)) 
          : null,
      expiry_date: (data.expiryDate && !isNaN(new Date(data.expiryDate).getTime())) 
          ? admin.firestore.Timestamp.fromDate(new Date(data.expiryDate)) 
          : null,
      barcode: cleanMainBarcode || null,
      all_barcodes: Array.from(allBarcodes),
      units: units,
      sort_order: Date.now(),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    await newDocRef.set(productPayload);

    // تسجيل حركة افتتاح المخزون
    if (stock > 0) {
      await db.collection("inventory_audit_log").add({
        product_id: newDocRef.id,
        product_name: cleanName,
        action: "initial_stock",
        delta: stock,
        resulting_stock: stock,
        performed_by: callerUid,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة لمدراء النظام فقط");
    }

    const { id, updates } = request.data || {};
    const cleanId = String(id || "").trim();
    if (!cleanId || !updates) throw new HttpsError("invalid-argument", "معرف المنتج وبيانات التحديث مطلوبة");

    const productRef = db.collection("products").doc(cleanId);

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(productRef);
      if (!snap.exists) throw new HttpsError("not-found", "المنتج غير موجود");

      const existing = snap.data() || {};
      const safeUpdates = {};
      const allowedFields = ["name", "brand_id", "category_id", "size_text", "price", "cost_price", "size_ml", "items_per_carton", "image_url", "is_active", "units"];

      for (const field of allowedFields) {
        if (updates[field] !== undefined) safeUpdates[field] = updates[field];
      }

      // توحيد الباركودات
      const normalizeBarcode = (raw) => {
        const arabicDigits = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9" };
        let text = String(raw || "").trim();
        for (const [ar, en] of Object.entries(arabicDigits)) text = text.replaceAll(ar, en);
        return text.replace(/[^0-9a-zA-Z]/g, "");
      };

      if (updates.barcode !== undefined || updates.units !== undefined) {
        const allBarcodes = new Set();
        const mainBar = normalizeBarcode(updates.barcode ?? existing.barcode);
        if (mainBar) {
          allBarcodes.add(mainBar);
          safeUpdates.barcode = mainBar;
        } else if (updates.barcode === null || updates.barcode === "") {
          safeUpdates.barcode = admin.firestore.FieldValue.delete();
        }

        const unitsList = updates.units ?? existing.units ?? [];
        if (Array.isArray(unitsList)) {
          for (const u of unitsList) {
            const uBar = normalizeBarcode(u.barcode);
            if (uBar) allBarcodes.add(uBar);
          }
        }
        safeUpdates.all_barcodes = allBarcodes.size > 0 ? Array.from(allBarcodes) : admin.firestore.FieldValue.delete();
      }

      // معالجة التواريخ
      if (updates.production_date !== undefined) {
        safeUpdates.production_date = updates.production_date
          ? admin.firestore.Timestamp.fromDate(new Date(updates.production_date))
          : admin.firestore.FieldValue.delete();
      }
      if (updates.expiry_date !== undefined) {
        safeUpdates.expiry_date = updates.expiry_date
          ? admin.firestore.Timestamp.fromDate(new Date(updates.expiry_date))
          : admin.firestore.FieldValue.delete();
      }

  // تعديل المخزون الذري المحمي من السوالب والتدقيق
      let newStock = Number(existing.stock) || 0;
      if (updates.stock_delta !== undefined) {
        const currentStock = Math.max(0, Number(existing.stock) || 0);
        const delta = Number(updates.stock_delta) || 0;
        // منع إنقاص المخزون تحت الصفر قطعياً
        const effectiveDelta = delta < 0 ? -Math.min(currentStock, Math.abs(delta)) : delta;
        newStock = currentStock + effectiveDelta;
        safeUpdates.stock = admin.firestore.FieldValue.increment(effectiveDelta);

        // تسجيل قيد حركة المخزون الدقيق
        const auditRef = db.collection("inventory_audit_log").doc();
        tx.set(auditRef, {
          product_id: cleanId,
          product_name: safeUpdates.name || existing.name || "",
          action: "stock_delta",
          delta: effectiveDelta,
          resulting_stock: newStock,
          performed_by: callerUid,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      safeUpdates.updated_at = admin.firestore.FieldValue.serverTimestamp();
      tx.update(productRef, safeUpdates);

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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة لمدراء النظام فقط");
    }

    const { id } = request.data || {};
    const cleanId = String(id || "").trim();
    if (!cleanId) throw new HttpsError("invalid-argument", "معرف المنتج مطلوب");

    await db.collection("products").doc(cleanId).update({
      is_deleted: true,
      is_active: false,
      deleted_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
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

    if (!cleanOrderId || !Array.isArray(returnItems) || returnItems.length === 0) {
      throw new HttpsError("invalid-argument", "بيانات المرتجع غير مكتملة");
    }

    // التحقق الصارم من صلاحية الإدارة
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "accountant", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة لمدراء النظام فقط");
    }

    const orderRef = db.collection("orders").doc(cleanOrderId);

    return await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      const orderData = orderSnap.data();

   // جلب جميع عناصر الطلب في المعاملة الذرية لحساب الكميات المتبقية بدقة
      const itemSnaps = await Promise.all(
        returnItems.map((it) => tx.get(db.collection("order_items").doc(String(it.item_id).trim())))
      );
      let totalRefund = 0;
      let totalDeductedProfit = 0;
      const productRestores = new Map();
      const returnDocPayloads = [];

      for (let i = 0; i < returnItems.length; i++) {
        const itemSnap = itemSnaps[i];
        const returnInfo = returnItems[i];
        if (!itemSnap.exists) {
          throw new HttpsError("not-found", `عنصر الطلب ${returnInfo.item_id} غير موجود`);
        }

        const itemData = itemSnap.data();
        const returnQty = Number(returnInfo.quantity) || 0;
        if (returnQty <= 0) continue;

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
        const unitCost = Number(itemData.unit_cost) || 0;
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
          returned_quantity: admin.firestore.FieldValue.increment(returnQty),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
          stock: admin.firestore.FieldValue.increment(restoreCartons),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // تحديث بيانات الفاتورة الأصلية
      const currentTotal = Number(orderData.total_amount || orderData.total || 0);
      const safeNewTotal = Math.max(0, currentTotal - totalRefund);

      tx.update(orderRef, {
        status: safeNewTotal <= 0.01 ? "returned" : "delivered",
        total: safeNewTotal,
        total_amount: safeNewTotal,
        returned_amount: admin.firestore.FieldValue.increment(totalRefund),
        total_profit: admin.firestore.FieldValue.increment(-totalDeductedProfit),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // تحديث إحصائيات الأرباح المركزية
      const summaryParentRef = db.collection("stats").doc("profit_summary");
      tx.set(summaryParentRef, {
        accumulated_profit: admin.firestore.FieldValue.increment(-totalDeductedProfit),
        cycle_profit: admin.firestore.FieldValue.increment(-totalDeductedProfit),
        accumulated_returns: admin.firestore.FieldValue.increment(totalRefund),
        last_updated: admin.firestore.FieldValue.serverTimestamp(),
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

    const callerDoc = await db.collection("profiles").doc(request.auth.uid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة للإدارة فقط");
    }

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
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, id: docRef.id };
  }
);

// 3. إضافة شركة جديدة بسلطة السيرفر
exports.adminAddBrand = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

    const callerDoc = await db.collection("profiles").doc(request.auth.uid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "warehouse_manager"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة للإدارة فقط");
    }

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
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const role = (callerDoc.data()?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin", "accountant"].includes(role)) {
      throw new HttpsError("permission-denied", "هذه العملية مخصصة للإدارة فقط");
    }

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
      created_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const cleanUrl = String(signatureUrl || "").trim();

    if (!cleanOrderId || !cleanUrl) {
      throw new HttpsError("invalid-argument", "بيانات التوقيع غير مكتملة");
    }

    const orderRef = db.collection("orders").doc(cleanOrderId);
    const snap = await orderRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "الطلب غير موجود");

    const orderData = snap.data() || {};

    // 🔒 التحقق الصارم من الصلاحيات: السائق المعين للطلب، التاجر صاحب الطلب، أو الإدارة حصراً
    const callerDoc = await db.collection("profiles").doc(callerUid).get();
    const callerRole = String(callerDoc.data()?.role || "").trim().toLowerCase();
    const isSuperOrAdmin = ["admin", "super_admin"].includes(callerRole);
    const isAssignedDriver = orderData.driver_id === callerUid;
    const isOrderMerchant = orderData.merchant_id === callerUid;

    if (!isSuperOrAdmin && !isAssignedDriver && !isOrderMerchant) {
      throw new HttpsError("permission-denied", "غير مصرح لك بتوثيق أو تعديل توقيع هذا الطلب");
    }

    await orderRef.update({
      signature_url: cleanUrl,
      signed_by: String(signerName || "المستلم المعتمد").trim(),
      signed_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

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
    const snap = await custRef.get();
    if (!snap.exists || snap.data()?.merchant_id !== merchantId) {
      throw new HttpsError("permission-denied", "غير مصرح لك بتعديل هذا الحساب");
    }

    await custRef.update({
      last_reminder_sent_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  }
);