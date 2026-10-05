import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../services/admin_service.dart';
import 'catalog_providers.dart';
import 'catalog_helpers.dart';
import 'catalog_widgets.dart';

class CategoriesTab extends ConsumerWidget {
  const CategoriesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(adminCategoriesProvider).when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: Colors.red[300]),
                const SizedBox(height: 12),
                const Text('فشل التحميل',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 15)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(adminCategoriesProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ],
            ),
          ),
          data: (list) => Column(
            children: [
              // فورم الإضافة
              AddWithImageBar(
                hint: 'اسم الصنف',
                onAdd: (name, imageUrl) async {
                  await ref
                      .read(adminServiceProvider)
                      .addCategory(name, imageUrl: imageUrl);
                  ref.invalidate(adminCategoriesProvider);
                },
              ),
              // عداد الأصناف
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${list.length} صنف',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ),
                  ),
                ),

              // القائمة
              Expanded(
                child: list.isEmpty
                    ? const CatalogEmptyState(
                        label: 'لا توجد أصناف', icon: Icons.category_outlined)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _CategoryTile(
                          name: list[i]['name'] ?? '',
                          imageUrl: list[i]['image_url'],
                          onDelete: () async {
                            if (await confirmDelete(
                                context, list[i]['name'] ?? '')) {
                              await ref
                                  .read(adminServiceProvider)
                                  .deleteCategory(list[i]['id'].toString());
                              ref.invalidate(adminCategoriesProvider);
                              ref.invalidate(brandsProvider);
                              ref
                                  .read(adminProductsProvider.notifier)
                                  .loadInitial();
                            }
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
  }
}

// ════════════════════════════════════════
// كارت الصنف
// ════════════════════════════════════════
class _CategoryTile extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.name,
    required this.onDelete,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          // صورة الصنف
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(16)),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),

          // الاسم والوصف
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.image_rounded,
                        size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      imageUrl != null && imageUrl!.isNotEmpty
                          ? 'يحتوي صورة'
                          : 'بدون صورة',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: Colors.grey[400]),
                    ),
                  ]),
                ],
              ),
            ),
          ),

          // زر الحذف
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_rounded,
                    color: Colors.red, size: 18),
              ),
            ),
          ),

          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 72,
        height: 72,
        color: AppColors.primary.withValues(alpha: 0.06),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0] : 'ص',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.primary),
          ),
        ),
      );
}

// ════════════════════════════════════════
// فورم إضافة صنف
// ════════════════════════════════════════
class AddWithImageBar extends StatefulWidget {
  final String hint;
  final Future<void> Function(String name, String? imageUrl) onAdd;
  const AddWithImageBar({super.key, required this.hint, required this.onAdd});

  @override
  State<AddWithImageBar> createState() => _AddWithImageBarState();
}

class _AddWithImageBarState extends State<AddWithImageBar> {
  final _ctrl = TextEditingController();
  XFile? _image;
  Uint8List? _imageBytes;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _error = null);
    final (file, bytes) = await pickCatalogImage();
    if (file != null && bytes != null) {
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        setState(() => _error = 'الصورة أكبر من 3MB');
        return;
      }
      setState(() {
        _image = file;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_ctrl.text.trim().isEmpty) {
      setState(() => _error = 'اسم الصنف مطلوب');
      return;
    }
    setState(() => _loading = true);
    try {
      final imageUrl =
          _image != null ? await uploadCatalogImage(_image!) : null;
      if (!mounted) return;
      await widget.onAdd(_ctrl.text.trim(), imageUrl);
      if (!mounted) return;
      _ctrl.clear();
      setState(() {
        _image = null;
        _imageBytes = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل الحفظ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 14)
          ],
        ),
        child: Column(
          children: [
            // منطقة اختيار الصورة
            GestureDetector(
              onTap: _loading ? null : _pickImage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: double.infinity,
                height: 72,
                decoration: BoxDecoration(
                  color: _imageBytes != null
                      ? AppColors.primary.withValues(alpha: 0.04)
                      : const Color(0xFFF8FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _imageBytes != null
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    // مربع الصورة المصغّرة
                    Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _imageBytes != null
                            ? Image.memory(_imageBytes!,
                                width: 48, height: 48, fit: BoxFit.cover)
                            : Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    color: AppColors.primary,
                                    size: 22),
                              ),
                      ),
                      if (_imageBytes != null)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.primary, width: 2),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 12),

                    // النص التوضيحي
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _imageBytes != null
                                ? 'تم اختيار الصورة ✓'
                                : 'صورة الصنف (اختياري)',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _imageBytes != null
                                    ? AppColors.primary
                                    : Colors.grey[600]),
                          ),
                          Text(
                            _imageBytes != null
                                ? '${(_imageBytes!.lengthInBytes / 1024).toStringAsFixed(0)} KB'
                                : 'أقل من 3MB • PNG, JPG',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),

                    // زر إزالة الصورة
                    if (_imageBytes != null)
                      GestureDetector(
                        onTap: () => setState(() {
                          _image = null;
                          _imageBytes = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Colors.red),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // حقل الاسم + زر الإضافة
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: !_loading,
                  decoration: catalogInputDec(widget.hint),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  onSubmitted: (_) => _submit(),
                  textInputAction: TextInputAction.done,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: _loading ? null : _submit,
                  child: CatalogAddBtn(loading: _loading)),
            ]),

            // رسالة الخطأ
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.red))),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
