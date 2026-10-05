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
  { secrets: [smsSenderId, smsApiKey] },
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
 
    if (purpose === "login" && profileSnap.empty) {
      return { success: false, message: "هذا الرقم غير مسجل، يرجى إنشاء حساب" };
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
  { secrets: [smsSenderId, smsApiKey] },
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
 
    // تضمين الـ role داخل التوكن المشفر لمنح الصلاحيات لقواعد فايرستور فوراً
    await admin.auth().setCustomUserClaims(uid, { role, purpose });
    const customToken = await admin.auth().createCustomToken(uid, { role, purpose });
    return { verified: true, message: "تم التحقق بنجاح", customToken };
  }
);

// ─── إرسال الإشعارات للهواتف ───
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

    const message = {
      token: fcmToken,
      notification: { title, body },
      android: {
        priority: "high",
        notification: {
          sound: "sala_notification", 
          channelId: "sala_orders_channel_v2"
        }
      },
      apns: {
        payload: {
          aps: {
            sound: "sala_notification.wav",
            contentAvailable: true,
          }
        }
      },
      data: {
        type: String(type),
        route: type === "order_status" ? "/merchant" : "/notifications"
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
  { region: "us-central1", cors: true },
  async (request) => {
    const query = String(request.data?.query || "").trim();
    if (!query) return [];

    const apiKey = "AIzaSyDIWBNhFJU2OGwrlFKv85c1S9bLNQmRmw8";
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
exports.checkPhoneNumber = onCall(async (request) => {
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

// ─── إنشاء ملف التاجر الجديد عند إكمال التسجيل (كانت مفقودة) ───
exports.createUserProfile = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
    }

    const uid = request.auth.uid;
    const { fullName, storeName, latitude, longitude, phone } = request.data || {};

    if (!fullName || !storeName || latitude == null || longitude == null || !phone) {
        throw new HttpsError('invalid-argument', 'جميع بيانات التسجيل مطلوبة');
    }

    try {
 await admin.auth().setCustomUserClaims(uid, { role: 'merchant', purpose: 'signup' });
        await db.collection('profiles').doc(uid).set({
            full_name: String(fullName).trim(),
            store_name: String(storeName).trim(),
            phone_number: String(phone).trim(),
            latitude: Number(latitude),
            longitude: Number(longitude),
            role: 'merchant',
            is_active: false,
            is_banned: false,
            account_status: 'pending',
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        return { success: true };
    } catch (error) {
        throw new HttpsError('internal', 'تعذر حفظ بيانات الحساب: ' + error.message);
    }
});

// ─── حذف الحساب لجوجل بلاي ───
exports.deleteUserAccount = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
    }

    const targetUid = request.auth.uid;

    try {
        await admin.auth().deleteUser(targetUid);
        await db.collection('profiles').doc(targetUid).update({
            is_active: false,
            is_banned: true, 
            is_deleted: true,
            phone_number: admin.firestore.FieldValue.delete(), 
            full_name: "مستخدم محذوف",
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
        return { success: true };
    } catch (error) {
        throw new HttpsError('internal', 'فشل حذف الحساب: ' + error.message);
    }
});