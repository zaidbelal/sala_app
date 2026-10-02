import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../services/admin_service.dart';
import 'catalog_providers.dart';
import 'catalog_helpers.dart';
import 'catalog_widgets.dart';

class BrandsTab extends ConsumerWidget {
  const BrandsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(adminCategoriesProvider);
    return ref.watch(brandsProvider).when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: Colors.red[300]),
                const SizedBox(height: 12),
                Text('فشل التحميل: $e',
                    style: const TextStyle(fontFamily: 'Cairo')),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(brandsProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          data: (list) => Column(
            children: [
              AddBrandBar(
                categories: categoriesAsync.value ?? [],
                onAdd: (name, categoryId, imageUrl) async {
                  await ref.read(adminServiceProvider).addBrand(
                      name: name, categoryId: categoryId, logoUrl: imageUrl);
                  ref.invalidate(brandsProvider);
                },
              ),
              // ── عداد ──
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${list.length} شركة',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ),
                  ]),
                ),
              Expanded(
                child: list.isEmpty
                    ? const CatalogEmptyState(
                        label: 'لا توجد شركات', icon: Icons.business_outlined)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final item = list[i];
                          final catId = item['category_id']?.toString();
                          final cat = (categoriesAsync.value ?? []).firstWhere(
                            (c) => c['id'].toString() == catId,
                            orElse: () => <String, dynamic>{},
                          );
                          return _BrandTile(
                            name: item['name'] ?? '',
                            categoryName: cat['name'] as String?,
                            logoUrl: item['logo_url'],
                            onDelete: () async {
                              if (await confirmDelete(
                                  context, item['name'] ?? '')) {
                                await ref
                                    .read(adminServiceProvider)
                                    .deleteBrand(item['id'].toString());
                                ref.invalidate(brandsProvider);
                                ref
                                    .read(adminProductsProvider.notifier)
                                    .loadInitial();
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
  }
}

// ════════════════════════════════════════
// كارت الشركة
// ════════════════════════════════════════
class _BrandTile extends StatelessWidget {
  final String name;
  final String? categoryName;
  final String? logoUrl;
  final VoidCallback onDelete;

  const _BrandTile({
    required this.name,
    required this.onDelete,
    this.categoryName,
    this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: logoUrl != null && logoUrl!.isNotEmpty
              ? Image.network(logoUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _logoPlaceholder(name))
              : _logoPlaceholder(name),
        ),
        title: Text(name,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        subtitle: categoryName != null
            ? Row(children: [
                const Icon(Icons.category_outlined,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(categoryName!,
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
              ])
            : null,
        trailing: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.delete_rounded, color: Colors.red, size: 18),
          ),
          onPressed: onDelete,
        ),
      ),
    );
  }

  Widget _logoPlaceholder(String name) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'B',
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.primary),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════
// فورم إضافة شركة
// ════════════════════════════════════════
class AddBrandBar extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final Future<void> Function(String name, String categoryId, String? imageUrl)
      onAdd;
  const AddBrandBar({super.key, required this.categories, required this.onAdd});

  @override
  State<AddBrandBar> createState() => _AddBrandBarState();
}

class _AddBrandBarState extends State<AddBrandBar> {
  final _ctrl = TextEditingController();
  String? _selectedCategoryId;
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
    final (file, bytes) = await pickCatalogImage(); // ← الدالة المحسّنة
    if (file != null && bytes != null) {
      // فحص حجم 3MB
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        setState(() => _error = 'الصورة كبيرة جداً، الحد الأقصى 3MB');
        return;
      }
      setState(() {
        _image = file;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _submit() async {
    if (!mounted) return;
    setState(() => _error = null);
    if (_ctrl.text.trim().isEmpty) {
      setState(() => _error = 'اسم الشركة مطلوب');
      return;
    }
    if (_selectedCategoryId == null) {
      setState(() => _error = 'اختر الصنف أولاً');
      return;
    }
    setState(() => _loading = true);
    try {
      final imageUrl =
          _image != null ? await uploadCatalogImage(_image!) : null;
      if (!mounted) return;
      final text = _ctrl.text.trim();
      final catId = _selectedCategoryId!;
      _ctrl.clear();
      if (mounted) {
        setState(() {
          _image = null;
          _imageBytes = null;
          _selectedCategoryId = null;
          _loading = false;
        });
      }
      await widget.onAdd(text, catId, imageUrl);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'فشل الإضافة: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── العنوان ──
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_business_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('إضافة شركة جديدة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),

          // ── اختيار الصورة ──
          GestureDetector(
            onTap: _loading ? null : _pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              height: 70,
              decoration: BoxDecoration(
                color: _imageBytes != null
                    ? AppColors.primary.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _imageBytes != null
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: _imageBytes != null ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _imageBytes != null
                        ? Image.memory(_imageBytes!,
                            width: 48, height: 48, fit: BoxFit.cover)
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add_photo_alternate_rounded,
                                color: AppColors.primary, size: 22),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _imageBytes != null
                              ? 'تم اختيار الشعار ✓'
                              : 'شعار الشركة (اختياري)',
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

          // ── اختيار الصنف ──
          DropdownButtonFormField<String>(
            initialValue: _selectedCategoryId,
            hint: const Text('اختر الصنف',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
            decoration: catalogInputDec(''),
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary),
            items: widget.categories
                .map((c) => DropdownMenuItem(
                      value: c['id'].toString(),
                      child: Text(c['name'] ?? '',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 13)),
                    ))
                .toList(),
            onChanged: _loading
                ? null
                : (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: 10),

          // ── اسم الشركة + زر ──
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: !_loading,
                decoration: catalogInputDec('اسم الشركة'),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                onSubmitted: (_) => _submit(),
                textInputAction: TextInputAction.done,
              ),
            ),
            const SizedBox(width: 10),
            _AddButton(loading: _loading, onTap: _submit),
          ]),

          // ── رسالة الخطأ ──
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
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
                            color: Colors.red)),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ── زر الإضافة ──
class _AddButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _AddButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: loading
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: loading
              ? []
              : [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              )
            : const Icon(Icons.add_rounded, color: Colors.white, size: 24),
      ),
    );
  }
}
