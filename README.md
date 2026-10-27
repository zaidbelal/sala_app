# سَلا

تطبيق Flutter لمنصة توصيل B2B، مع Firebase Authentication وCloud Firestore وCloud Functions.

## التطوير والتحقق

من مجلد `sala` شغّل:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
firebase emulators:exec --project demo-sala --only auth,firestore,storage "node test/security/firebase_rules_smoke_test.js"
firebase emulators:exec --project demo-sala --only auth,firestore,functions "node test/security/functions_financial_migration_test.js"
firebase emulators:exec --project demo-sala --only auth,firestore,functions "node test/security/functions_ledger_transactions_test.js"
```

## نشر خدمات Firebase

تأكد من اختيار مشروع Firebase الصحيح ومراجعة بيانات الحسابات ذات الأدوار الإدارية قبل النشر. تعيين الدور يتم عبر Cloud Functions موثوقة؛ لا تنشئ ملفات المستخدمين أو تغيّر أدوارهم مباشرة من التطبيق.

من مجلد `sala` انشر القواعد والفهارس والدوال بالأمر:

```powershell
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

لا يُنشر أي تغيير إلى Firebase تلقائياً من أوامر التطوير أو البناء.
