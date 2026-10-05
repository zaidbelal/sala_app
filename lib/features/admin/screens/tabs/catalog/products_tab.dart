import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../services/admin_service.dart';
import 'catalog_providers.dart';
import 'catalog_helpers.dart';
import 'catalog_widgets.dart';
import 'product_units_editor.dart';
import 'package:sala/core/models/product_unit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../merchant/barcode/barcode_scanner_screen.dart';

String formatFirestoreDate(dynamic value) {
  DateTime? date;

  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is DateTime) {
    date = value;
  } else if (value is String && value.trim().isNotEmpty) {
    date = DateTime.tryParse(value.trim());
  }

  if (date == null) return '';

  return '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 4 || i == 6) {
        buffer.write('-');
      }
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    int cursorPosition = formatted.length;
    if (newValue.selection.baseOffset < newValue.text.length) {
      cursorPosition = newValue.selection.baseOffset;
      if (cursorPosition == 5 || cursorPosition == 8) {
        cursorPosition++;
      }
      cursorPosition = cursorPosition.clamp(0, formatted.length);
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}

class ProductsTab extends ConsumerStatefulWidget {
  const ProductsTab({super.key});
  @override
  ConsumerState<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<ProductsTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final brandsAsync = ref.watch(brandsProvider);
    final productsAsync = ref.watch(adminProductsProvider);
    final brandsList = brandsAsync.value ?? [];

    return Column(
      children: [
        // ── 1. فورم الإضافة (حفظ ذري مباشر لجميع الحقول بما فيها الحجم المكتوب) ──
        AddProductBar(
          brands: brandsList,
          onAdd: (data) async {
            await ref.read(adminServiceProvider).addProduct(
                  name: data['name'],
                  brandId: data['brandId'],
                  price: data['price'],
                  costPrice: data['cost_price'],
                  itemsPerCarton: data['items'],
                  sizeMl: data['size'],
                  sizeText: data['size_text'],
                  stock: (data['stock'] as num?)?.toDouble() ?? 0.0,
                  imageUrl: data['imageUrl'],
                  productionDate: data['production_date'],
                  expiryDate: data['expiry_date'],
                  barcode: data['barcode'],
                  units: List<Map<String, dynamic>>.from(
                    data['units'] as List? ?? const [],
                  ),
                );
            // تحديث سلس في الخلفية بدون تفريغ الشاشة بـ loading
            ref.read(adminProductsProvider.notifier).loadInitial(silent: true);
          },
        ),

        // ── 2. شريط البحث والعداد ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'بحث عن منتج...',
                  hintStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      color: Color(0xFFAAAAAA),
                      fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Colors.grey, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? GestureDetector(
                          onTap: () => setState(() => _search = ''),
                          child: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.grey))
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                productsAsync.maybeWhen(
                  data: (l) => '${l.length}',
                  orElse: () => '0',
                ),
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ),
          ]),
        ),

        // ── 3. القائمة فقط هي التي تتغير حالتها (Loading / Error / Data) ──
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: Colors.red[300]),
                  const SizedBox(height: 12),
                  const Text('فشل تحميل المنتجات',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(adminProductsProvider.notifier).loadInitial(),
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
            data: (list) {
              final filtered = _search.isEmpty
                  ? list
                  : list
                      .where((p) => (p['name'] as String? ?? '')
                          .toLowerCase()
                          .contains(_search.toLowerCase()))
                      .toList();

              if (filtered.isEmpty) {
                return _search.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('لا نتائج لـ "$_search"',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                    color: Colors.grey[400])),
                          ],
                        ),
                      )
                    : const CatalogEmptyState(
                        label: 'لا توجد منتجات',
                        icon: Icons.inventory_2_outlined);
              }

              final hasMore =
                  ref.watch(adminProductsProvider.notifier).hasMore &&
                      _search.isEmpty;

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                itemCount: filtered.length + (hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == filtered.length) {
                    final isLoadingMore =
                        ref.watch(productsLoadingMoreProvider);
                    return Center(
                      child: TextButton.icon(
                        onPressed: isLoadingMore
                            ? null
                            : () => ref
                                .read(adminProductsProvider.notifier)
                                .loadMore(),
                        icon: isLoadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_downward_rounded),
                        label: const Text('تحميل المزيد',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700)),
                      ),
                    );
                  }
                  final brandId = filtered[i]['brand_id']?.toString();
                  final brand = brandsList.firstWhere(
                    (b) => b['id'].toString() == brandId,
                    orElse: () => <String, dynamic>{},
                  );
                  return _ProductTile(
                    product: filtered[i],
                    brandName: brand['name'] as String?,
                    onDelete: () async {
                      if (await confirmDelete(
                          context, filtered[i]['name'] ?? '')) {
                        await ref
                            .read(adminServiceProvider)
                            .deleteProduct(filtered[i]['id'].toString());
                        ref.read(adminProductsProvider.notifier).loadInitial();
                      }
                    },
                    onEdit: () =>
                        _showEditSheet(context, ref, filtered[i], brandsList),
                    onToggleActive: (val) async {
                      await ref.read(adminServiceProvider).updateProduct(
                          filtered[i]['id'].toString(), {'is_active': val});
                      ref.read(adminProductsProvider.notifier).loadInitial();
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref,
      Map<String, dynamic> product, List<Map<String, dynamic>> brands) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProductEditSheet(
        product: product,
        brands: brands,
        onSaved: () {
          ref.read(adminProductsProvider.notifier).loadInitial();
        },
      ),
    );
  }
}

// ════════════════════════════════════════
// كارت المنتج
// ════════════════════════════════════════
class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? brandName;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;

  const _ProductTile({
    required this.product,
    required this.onDelete,
    required this.onEdit,
    required this.onToggleActive,
    this.brandName,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = product['image_url'] as String?;
    final price = (product['price'] as num?)?.toStringAsFixed(0) ?? '0';
    final double rawStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final bool isIntegerStock = (rawStock - rawStock.round()).abs() < 0.001;
    final stockStr = isIntegerStock
        ? rawStock.round().toString()
        : rawStock.toStringAsFixed(2);
    final stock = rawStock;
    final isActive = product['is_active'] as bool? ?? true;
    final expiryDate = formatFirestoreDate(product['expiry_date']);
    final costPrice = (product['cost_price'] as num?)?.toDouble() ?? 0;
    final salePrice = (product['price'] as num?)?.toDouble() ?? 0;
    final profit = salePrice - costPrice;
    final rawUnits = product['units'];

    final units = rawUnits is List
        ? rawUnits
            .whereType<Map>()
            .map((unit) => Map<String, dynamic>.from(unit))
            .toList()
        : <Map<String, dynamic>>[];
    final stockColor = stock > 10
        ? Colors.green
        : stock > 0
            ? Colors.orange
            : Colors.red;

    bool isExpiringSoon = false;
    bool isExpired = false;
    if (expiryDate.isNotEmpty) {
      final exp = DateTime.tryParse(expiryDate);
      if (exp != null) {
        final now = DateTime.now();
        isExpired = exp.isBefore(now);
        isExpiringSoon =
            !isExpired && exp.isBefore(now.add(const Duration(days: 30)));
      }
    }

    final sizeDisplay =
        (product['size_text']?.toString().trim().isNotEmpty ?? false)
            ? product['size_text'].toString().trim()
            : (product['size_ml'] != null ? '${product['size_ml']} مل' : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !isActive
              ? Colors.red.withValues(alpha: 0.2)
              : isExpired
                  ? Colors.red.withValues(alpha: 0.2)
                  : isExpiringSoon
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(0),
                ),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(imageUrl,
                        width: 80,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _placeholder(product['name'] ?? ''))
                    : _placeholder(product['name'] ?? ''),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(product['name'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                        ),
                        if (!isActive)
                          _tag('متوقف', Colors.red)
                        else if (isExpired)
                          _tag('منتهي', Colors.red)
                        else if (isExpiringSoon)
                          _tag('ينتهي قريباً', Colors.orange),
                      ]),
                      if (brandName != null) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.business_rounded,
                              size: 11, color: Colors.grey[400]),
                          const SizedBox(width: 3),
                          Text(brandName!,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.grey[500])),
                        ]),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _badge(
                            '$price ر.ي',
                            AppColors.primary,
                            Icons.sell_rounded,
                          ),
                          if (costPrice > 0)
                            _badge(
                              'ربح ${profit.toStringAsFixed(0)} ر.ي',
                              profit > 0 ? Colors.teal : Colors.red,
                              Icons.trending_up_rounded,
                            ),
                          _badge(
                            '$stockStr كرتون',
                            stockColor,
                            Icons.inventory_2_rounded,
                          ),
                          if (sizeDisplay != null && sizeDisplay.isNotEmpty)
                            _badge(
                              sizeDisplay,
                              Colors.blue,
                              Icons.straighten_rounded,
                            ),
                          if (product['barcode'] != null &&
                              product['barcode'].toString().trim().isNotEmpty)
                            _badge(
                              product['barcode'].toString().trim(),
                              Colors.indigo,
                              Icons.qr_code_2_rounded,
                            ),
                        ],
                      ),
                      if (units.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: units.map((unit) {
                            final label =
                                unit['label']?.toString().trim() ?? '';
                            final unitPrice =
                                (unit['price'] as num?)?.toDouble() ?? 0;
                            final unitQty = (unit['qty'] as num?)?.toInt() ?? 0;

                            final unitText = [
                              if (label.isNotEmpty) label,
                              '${unitPrice.toStringAsFixed(0)} ر.ي',
                              if (unitQty > 0) '$unitQty حبة',
                            ].join(' • ');

                            return _badge(
                              unitText,
                              Colors.deepPurple,
                              Icons.inventory_2_outlined,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFB),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(children: [
              _ActionBtn(
                icon: isActive
                    ? Icons.toggle_on_rounded
                    : Icons.toggle_off_rounded,
                label: isActive ? 'نشط' : 'متوقف',
                color: isActive ? Colors.green : Colors.grey,
                onTap: () => onToggleActive(!isActive),
              ),
              _Divider(),
              _ActionBtn(
                icon: Icons.edit_rounded,
                label: 'تعديل',
                color: AppColors.primary,
                onTap: onEdit,
              ),
              _Divider(),
              _ActionBtn(
                icon: Icons.delete_rounded,
                label: 'حذف',
                color: Colors.red,
                onTap: onDelete,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(String name) => Container(
        width: 80,
        height: 90,
        color: AppColors.primary.withValues(alpha: 0.06),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'P',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.primary),
          ),
        ),
      );

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w700)),
      );

  Widget _badge(String label, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ]),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: Colors.grey[200]);
}

// ════════════════════════════════════════
// فورم إضافة منتج
// ════════════════════════════════════════
class AddProductBar extends StatefulWidget {
  final List<Map<String, dynamic>> brands;
  final Future<void> Function(Map<String, dynamic> data) onAdd;
  const AddProductBar({super.key, required this.brands, required this.onAdd});

  @override
  State<AddProductBar> createState() => _AddProductBarState();
}

class _AddProductBarState extends State<AddProductBar> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _itemsCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _prodCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  String? _selectedBrandId;
  XFile? _image;
  Uint8List? _imageBytes;
  bool _loading = false;
  String? _error;
  List<ProductUnit> _units = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _itemsCtrl.dispose();
    _sizeCtrl.dispose();
    _stockCtrl.dispose();
    _prodCtrl.dispose();
    _expCtrl.dispose();
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

  void _clearForm() {
    for (final c in [
      _nameCtrl,
      _priceCtrl,
      _costCtrl,
      _stockCtrl,
      _itemsCtrl,
      _sizeCtrl,
      _prodCtrl,
      _expCtrl
    ]) {
      c.clear();
    }
    setState(() {
      _image = null;
      _imageBytes = null;
      _selectedBrandId = null;
      _error = null;
      _units = [];
      _loading = false;
    });
  }

  Future<void> _submit(BuildContext sheetCtx, StateSetter setSt) async {
    setSt(() => _error = null);
    if (_nameCtrl.text.trim().isEmpty) {
      setSt(() => _error = 'اسم المنتج مطلوب');
      return;
    }
    if (_selectedBrandId == null) {
      setSt(() => _error = 'اختر الشركة أولاً');
      return;
    }
    if (_priceCtrl.text.isEmpty) {
      setSt(() => _error = 'السعر مطلوب');
      return;
    }

    setSt(() => _loading = true);
    setState(() => _loading = true);
    try {
      final imageUrl =
          _image != null ? await uploadCatalogImage(_image!) : null;
      final sizeInput = _sizeCtrl.text.trim();
      final numericSize =
          double.tryParse(sizeInput.replaceAll(RegExp(r'[^0-9.]'), ''));
      final payload = {
        'name': _nameCtrl.text.trim(),
        'brandId': _selectedBrandId,
        'price': double.tryParse(_priceCtrl.text) ?? 0,
        'cost_price': double.tryParse(_costCtrl.text) ?? 0,
        'stock': double.tryParse(_stockCtrl.text) ?? 0.0,
        'items': int.tryParse(_itemsCtrl.text),
        'size': numericSize,
        'size_text': sizeInput,
        'barcode':
            _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
        'production_date':
            _prodCtrl.text.trim().isEmpty ? null : _prodCtrl.text.trim(),
        'expiry_date':
            _expCtrl.text.trim().isEmpty ? null : _expCtrl.text.trim(),
        'imageUrl': imageUrl,
        'units': _units.map((u) => u.toMap()).toList(),
      };

      // تنفيذ الحفظ كاملاً أولاً
      await widget.onAdd(payload);

      // تنظيف النموذج وإعادة ضبط حالة التحميل
      _clearForm();

      // الإغلاق الآمن بعد انتهاء الحفظ بنجاح تام
      if (sheetCtx.mounted && Navigator.of(sheetCtx).canPop()) {
        Navigator.of(sheetCtx).pop();
      }
    } catch (e) {
      if (sheetCtx.mounted) {
        setSt(() {
          _loading = false;
          _error = 'فشل الحفظ: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openSheet() {
    setState(() {
      _loading = false;
      _error = null;
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF5F7FA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.add_circle_outline_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('إضافة منتج جديد',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ]),
                ),
                const Divider(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        GestureDetector(
                          onTap: _loading
                              ? null
                              : () async {
                                  await _pickImage();
                                  setSt(() {});
                                },
                          child: Container(
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
                                      : Colors.grey.withValues(alpha: 0.2)),
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _imageBytes != null
                                      ? Image.memory(_imageBytes!,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover)
                                      : Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.07),
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          child: const Icon(
                                              Icons.add_photo_alternate_rounded,
                                              size: 22,
                                              color: AppColors.primary)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(
                                  _imageBytes != null
                                      ? 'تم اختيار الصورة ✓'
                                      : 'صورة المنتج (اختياري) • PNG, JPG أقل من 3MB',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: _imageBytes != null
                                          ? AppColors.primary
                                          : Colors.grey[500]),
                                )),
                                if (_imageBytes != null)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _image = null;
                                        _imageBytes = null;
                                      });
                                      setSt(() {});
                                    },
                                    child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                            color: Colors.red
                                                .withValues(alpha: 0.1),
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close_rounded,
                                            size: 14, color: Colors.red)),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBrandId,
                          hint: const Text('اختر الشركة *',
                              style:
                                  TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                          decoration: catalogInputDec(''),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppColors.primary),
                          items: widget.brands
                              .map((b) => DropdownMenuItem(
                                    value: b['id'].toString(),
                                    child: Text(b['name'] ?? '',
                                        style: const TextStyle(
                                            fontFamily: 'Cairo', fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: _loading
                              ? null
                              : (v) => setSt(() => _selectedBrandId = v),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameCtrl,
                          enabled: !_loading,
                          onChanged: (_) => setSt(() {}),
                          decoration: catalogInputDec('اسم المنتج *'),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: CatalogSmallField(
                                  ctrl: _priceCtrl,
                                  hint: 'السعر ر.ي *',
                                  type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: CatalogSmallField(
                                  ctrl: _costCtrl,
                                  hint: 'سعر الشراء 🔒',
                                  type: TextInputType.number)),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: CatalogSmallField(
                                  ctrl: _stockCtrl,
                                  hint: 'مخزون كرتون',
                                  type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: CatalogSmallField(
                                  ctrl: _itemsCtrl,
                                  hint: 'حبات/كرتون',
                                  type: TextInputType.number)),
                        ]),
                        const SizedBox(height: 8),
                        // ── إدخال الحجم/الكمية كنص حر تكتبه بيدك ──
                        CatalogSmallField(
                            ctrl: _sizeCtrl,
                            hint:
                                'الحجم أو الكمية (اكتب بيدك: مثال 1.5 لتر ، 10 كجم ، 500 مل)',
                            type: TextInputType.text),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: CatalogSmallField(
                                ctrl: _barcodeCtrl,
                                hint:
                                    'الباركود الدولي (أدخل يدوياً أو امسح بالكاميرا)',
                                type: TextInputType.text,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                final scanned =
                                    await BarcodeScannerScreen.scan(context);
                                if (scanned != null && scanned.isNotEmpty) {
                                  _barcodeCtrl.text = scanned;
                                  setSt(() {});
                                }
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.qr_code_scanner_rounded,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ── إدخال التواريخ يدوياً بسلاسة ──
                        Row(children: [
                          Expanded(
                            child: _ManualDateField(
                              ctrl: _prodCtrl,
                              hint: 'إنتاج: 2026-05-15',
                              icon: Icons.calendar_today_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ManualDateField(
                              ctrl: _expCtrl,
                              hint: 'انتهاء: 2027-05-15',
                              icon: Icons.event_busy_rounded,
                            ),
                          ),
                        ]),
                        ProductUnitsEditor(
                          productName: _nameCtrl.text.trim(),
                          initialUnits: _units,
                          onChanged: (units) {
                            _units = units;
                            setSt(() {});
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(10)),
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
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed:
                                _loading ? null : () => _submit(ctx, setSt),
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: Text(
                                _loading ? 'جاري الرفع...' : 'حفظ المنتج',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GestureDetector(
        onTap: _openSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child:
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_circle_outline_rounded,
                color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('إضافة منتج جديد',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// حقل إدخال التاريخ اليدوي المباشر السريع مع التنسيق التلقائي
// ══════════════════════════════════════════════════════════
class _ManualDateField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;

  const _ManualDateField({
    required this.ctrl,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        DateInputFormatter(),
      ],
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          color: Color(0xFFAAAAAA),
        ),
        prefixIcon: Icon(icon, size: 16, color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFFF8FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// نافذة تعديل المنتج الشاملة (تعديل كل شيء + كتابة الحجم يدوياً)
// ══════════════════════════════════════════════════════════
class _ProductEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> brands;
  final VoidCallback onSaved;

  const _ProductEditSheet({
    required this.product,
    required this.brands,
    required this.onSaved,
  });
  @override
  ConsumerState<_ProductEditSheet> createState() => _ProductEditSheetState();
}

class _ProductEditSheetState extends ConsumerState<_ProductEditSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController costCtrl;
  late final TextEditingController stockCtrl;
  late final TextEditingController itemsCtrl;
  late final TextEditingController sizeCtrl;
  late final TextEditingController prodCtrl;
  late final TextEditingController expCtrl;
  late final TextEditingController barcodeCtrl;
  late double initialStockValue;
  late List<ProductUnit> editUnits;
  String? selectedBrandId;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    // 1. اسم المنتج
    nameCtrl = TextEditingController(text: p['name']?.toString() ?? '');
    // 2. الشركة
    selectedBrandId = p['brand_id']?.toString();
    // 3. الأسعار والمخزون وحبات الكرتون
    priceCtrl =
        TextEditingController(text: (p['price'] as num?)?.toString() ?? '');
    costCtrl = TextEditingController(
        text: (p['cost_price'] as num?)?.toString() ?? '');
    itemsCtrl = TextEditingController(
        text: (p['items_per_carton'] as num?)?.toString() ?? '');

    initialStockValue = (p['stock'] as num?)?.toDouble() ?? 0.0;
    final bool isInitialInteger =
        (initialStockValue - initialStockValue.round()).abs() < 0.001;
    stockCtrl = TextEditingController(
      text: isInitialInteger
          ? initialStockValue.round().toString()
          : initialStockValue.toStringAsFixed(2),
    );

    // 4. الحجم الحر (يكتب التاجر ما يريد بيده: 1.5 لتر أو 10 كجم أو 500 مل أو يتركه فارغاً)
    sizeCtrl = TextEditingController(
      text: p['size_text']?.toString() ??
          (p['size_ml'] != null ? '${p['size_ml']} مل' : ''),
    );

    // 5. التواريخ
    prodCtrl =
        TextEditingController(text: formatFirestoreDate(p['production_date']));
    expCtrl =
        TextEditingController(text: formatFirestoreDate(p['expiry_date']));
    barcodeCtrl = TextEditingController(text: p['barcode']?.toString() ?? '');
    // 6. الوحدات والكميات
    editUnits = (p['units'] as List<dynamic>? ?? [])
        .map((e) => ProductUnit.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    stockCtrl.dispose();
    itemsCtrl.dispose();
    sizeCtrl.dispose();
    prodCtrl.dispose();
    expCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('تعديل المنتج بالكامل',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            const Divider(height: 20),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 1. اسم المنتج ──
                        CatalogEditField(
                          ctrl: nameCtrl,
                          hint: 'اسم المنتج *',
                          icon: Icons.edit_note_rounded,
                        ),
                        const SizedBox(height: 10),

                        // ── 2. اختيار / تغيير الشركة ──
                        DropdownButtonFormField<String>(
                          initialValue: selectedBrandId,
                          hint: const Text('اختر الشركة / الماركة *',
                              style:
                                  TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                          decoration: catalogInputDec('الشركة'),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppColors.primary),
                          items: widget.brands
                              .map((b) => DropdownMenuItem(
                                    value: b['id'].toString(),
                                    child: Text(b['name'] ?? '',
                                        style: const TextStyle(
                                            fontFamily: 'Cairo', fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => selectedBrandId = v),
                        ),
                        const SizedBox(height: 10),

                        // ── 3. السعر والمخزون ──
                        Row(children: [
                          Expanded(
                              child: CatalogEditField(
                                  ctrl: priceCtrl,
                                  hint: 'سعر البيع ر.ي *',
                                  icon: Icons.attach_money_rounded,
                                  type: TextInputType.number)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: CatalogEditField(
                                  ctrl: stockCtrl,
                                  hint: 'مخزون كرتون',
                                  icon: Icons.inventory_rounded,
                                  type: TextInputType.number)),
                        ]),
                        const SizedBox(height: 10),

                        // ── 4. سعر الشراء وحبات الكرتون ──
                        Row(children: [
                          Expanded(
                            child: CatalogEditField(
                                ctrl: costCtrl,
                                hint: 'سعر الشراء 🔒',
                                icon: Icons.lock_rounded,
                                type: TextInputType.number),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CatalogEditField(
                                ctrl: itemsCtrl,
                                hint: 'حبات بالكرتون',
                                icon: Icons.view_module_rounded,
                                type: TextInputType.number),
                          ),
                        ]),
                        const SizedBox(height: 10),

                        // ── 5. الحجم / الوزن / الكمية (تكتب ما تريده بيدك بدون أي قيود) ──
                        CatalogEditField(
                          ctrl: sizeCtrl,
                          hint:
                              'الحجم أو الكمية (اكتب بيدك: مثلاً 1.5 لتر ، 10 كجم ، 500 مل)',
                          icon: Icons.straighten_rounded,
                          type: TextInputType.text,
                        ),
                        const SizedBox(height: 10),

                        // ── الباركود الدولي للمنتج ──
                        Row(
                          children: [
                            Expanded(
                              child: CatalogEditField(
                                ctrl: barcodeCtrl,
                                hint:
                                    'الباركود الدولي (أدخل يدوياً أو امسح بالكاميرا)',
                                icon: Icons.qr_code_2_rounded,
                                type: TextInputType.text,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                final scanned =
                                    await BarcodeScannerScreen.scan(context);
                                if (scanned != null && scanned.isNotEmpty) {
                                  setState(() => barcodeCtrl.text = scanned);
                                }
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.qr_code_scanner_rounded,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // ── 6. تواريخ الإنتاج والانتهاء اليدوية ──
                        Row(children: [
                          Expanded(
                            child: _ManualDateField(
                              ctrl: prodCtrl,
                              hint: 'إنتاج: 2026-05-15',
                              icon: Icons.calendar_today_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ManualDateField(
                              ctrl: expCtrl,
                              hint: 'انتهاء: 2027-05-15',
                              icon: Icons.event_busy_rounded,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 7. محرر الوحدات والكميات ──
                  ProductUnitsEditor(
                    productName: nameCtrl.text.trim(),
                    initialUnits: editUnits,
                    onChanged: (units) {
                      setState(() => editUnits = units);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── زر حفظ التعديلات ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : _saveProductUpdates,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded, size: 20),
                      label: Text(
                          saving ? 'جاري الحفظ...' : 'حفظ التعديلات بالكامل',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProductUpdates() async {
    final nameText = nameCtrl.text.trim();
    if (nameText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('اسم المنتج مطلوب', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red),
      );
      return;
    }

    final newStockInput = double.tryParse(stockCtrl.text.trim());
    if (newStockInput != null && newStockInput < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا يمكن أن يكون المخزون سالباً',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (prodCtrl.text.trim().isNotEmpty &&
        DateTime.tryParse(prodCtrl.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('صيغة تاريخ الإنتاج غير صحيحة (مثال: 2026-05-15)',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (expCtrl.text.trim().isNotEmpty &&
        DateTime.tryParse(expCtrl.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('صيغة تاريخ الانتهاء غير صحيحة (مثال: 2027-05-15)',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => saving = true);

    final String originalStockText =
        (initialStockValue - initialStockValue.round()).abs() < 0.001
            ? initialStockValue.round().toString()
            : initialStockValue.toStringAsFixed(2);
    final bool stockWasManuallyChanged = newStockInput != null &&
        stockCtrl.text.trim() != originalStockText &&
        (newStockInput - initialStockValue).abs() > 0.01;

    String? categoryId;
    if (selectedBrandId != null) {
      final bMatch = widget.brands.firstWhere(
        (b) => b['id'].toString() == selectedBrandId,
        orElse: () => <String, dynamic>{},
      );
      categoryId = bMatch['category_id']?.toString();
    }

    final customSizeText = sizeCtrl.text.trim();
    final numericSize =
        double.tryParse(customSizeText.replaceAll(RegExp(r'[^0-9.]'), ''));
    try {
      await ref
          .read(adminServiceProvider)
          .updateProduct(widget.product['id'].toString(), {
        'name': nameText,
        if (selectedBrandId != null) 'brand_id': selectedBrandId,
        if (categoryId != null) 'category_id': categoryId,
        'price': double.tryParse(priceCtrl.text) ?? 0,
        if (costCtrl.text.isNotEmpty)
          'cost_price': double.tryParse(costCtrl.text),
        if (stockWasManuallyChanged) 'stock': newStockInput,
        if (itemsCtrl.text.isNotEmpty)
          'items_per_carton': int.tryParse(itemsCtrl.text),
        'size_text': customSizeText,
        if (numericSize != null) 'size_ml': numericSize,
        'barcode': barcodeCtrl.text.trim().isNotEmpty
            ? barcodeCtrl.text.trim()
            : FieldValue.delete(),
        'production_date': prodCtrl.text.trim().isNotEmpty &&
                DateTime.tryParse(prodCtrl.text.trim()) != null
            ? Timestamp.fromDate(DateTime.parse(prodCtrl.text.trim()))
            : FieldValue.delete(),
        'expiry_date': expCtrl.text.trim().isNotEmpty &&
                DateTime.tryParse(expCtrl.text.trim()) != null
            ? Timestamp.fromDate(DateTime.parse(expCtrl.text.trim()))
            : FieldValue.delete(),
        'units': editUnits.map((u) => u.toMap()).toList(),
      });

      widget.onSaved();

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل التحديث: $e',
                  style: const TextStyle(fontFamily: 'Cairo'))),
        );
      }
    }
  }
}
