import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

// ════════════════════════════════════════
// اختيار صورة مضغوطة (يمنع تجميد المتصفح)
// ════════════════════════════════════════
Future<(XFile?, Uint8List?)> pickCatalogImage() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,

    // ضغط وتصغير قوي للصورة
    maxWidth: 400,
    maxHeight: 400,
    imageQuality: 45,
  );

  if (picked == null) {
    return (null, null);
  }

  final bytes = await picked.readAsBytes();

  return (picked, bytes);
}

// ════════════════════════════════════════
// رفع الصورة مع فحص الحجم
// ════════════════════════════════════════
Future<String?> uploadCatalogImage(XFile file) async {
  final bytes = await file.readAsBytes();

  if (bytes.lengthInBytes > 3 * 1024 * 1024) {
    throw Exception('الصورة أكبر من 3MB');
  }

  final ext = file.name.split('.').last.toLowerCase();
  final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
  final contentType =
      safeExt == 'jpg' || safeExt == 'jpeg' ? 'image/jpeg' : 'image/$safeExt';
  final nonce = DateTime.now().microsecondsSinceEpoch.toString();
  final fileName = 'catalog_${nonce}_${file.name.hashCode.abs()}.$safeExt';

  final ref = FirebaseStorage.instance.ref().child('images').child(fileName);
  try {
    final snapshot = await ref
        .putData(
          bytes,
          SettableMetadata(contentType: contentType),
        )
        .timeout(const Duration(seconds: 15));

    if (snapshot.state != TaskState.success) {
      throw Exception('لم يكتمل رفع الصورة إلى Firebase Storage');
    }

    final downloadUrl =
        await snapshot.ref.getDownloadURL().timeout(const Duration(seconds: 6));

    if (downloadUrl.isEmpty) {
      throw Exception('لم يتم إنشاء رابط الصورة');
    }

    return downloadUrl;
  } on FirebaseException catch (e) {
    if (kDebugMode) {
      debugPrint('❌ فشل Firebase Storage: ${e.code} - ${e.message}');
    }
    rethrow;
  }
}

// ════════════════════════════════════════
// حوار تأكيد الحذف المُحسَّن
// ════════════════════════════════════════
Future<bool> confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.red.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: Colors.red, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('تأكيد الحذف',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: Colors.grey,
                    height: 1.6),
                children: [
                  const TextSpan(text: 'هل تريد حذف '),
                  TextSpan(
                    text: '"$name"',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.black87),
                  ),
                  const TextSpan(text: ' نهائياً؟\nلا يمكن التراجع عن هذا.'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFDDDDDD)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('إلغاء',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.grey,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('حذف',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

// ════════════════════════════════════════
// ديكور حقول الإدخال
// ════════════════════════════════════════
InputDecoration catalogInputDec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          fontFamily: 'Cairo', color: Color(0xFFAAAAAA), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            BorderSide(color: const Color(0xFF1B8E3D).withValues(alpha: 0.5)),
      ),
    );
