import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/models/product_unit.dart';
import 'package:image_picker/image_picker.dart';
import 'catalog_helpers.dart';

class _UnitDateInputFormatter extends TextInputFormatter {
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

/// ويدجت لإضافة/تعديل/حذف وحدات البيع للمنتج في لوحة الأدمن
class ProductUnitsEditor extends StatefulWidget {
  final String? productName;
  final List<ProductUnit> initialUnits;
  final ValueChanged<List<ProductUnit>> onChanged;

  const ProductUnitsEditor({
    super.key,
    this.productName,
    required this.initialUnits,
    required this.onChanged,
  });

  @override
  State<ProductUnitsEditor> createState() => _ProductUnitsEditorState();
}

class _ProductUnitsEditorState extends State<ProductUnitsEditor> {
  late List<ProductUnit> _units;

  @override
  void initState() {
    super.initState();
    _units = List.from(widget.initialUnits);
  }

  @override
  void didUpdateWidget(covariant ProductUnitsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUnits != widget.initialUnits) {
      _units = List.from(widget.initialUnits);
    }
  }

  void _add() async {
    final unit = await _showUnitDialog(context);
    if (unit == null) return;
    if (_units.any((u) => u.label.trim() == unit.label.trim())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('هذه الوحدة موجودة مسبقاً',
                style: TextStyle(fontFamily: 'Cairo')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    setState(() => _units.add(unit));
    widget.onChanged(_units);
  }

  void _remove(int index) {
    setState(() => _units.removeAt(index));
    widget.onChanged(_units);
  }

  void _edit(int index) async {
    final unit = await _showUnitDialog(context, existing: _units[index]);
    if (unit == null) return;
    final isDuplicate = _units.asMap().entries.any(
          (entry) =>
              entry.key != index &&
              entry.value.label.trim() == unit.label.trim(),
        );
    if (isDuplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('توجد كمية أخرى بنفس هذا الاسم مسبقاً',
                style: TextStyle(fontFamily: 'Cairo')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    setState(() => _units[index] = unit);
    widget.onChanged(_units);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.productName != null &&
            widget.productName!.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.productName!.trim(),
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // ── العنوان + زر الإضافة ──
        Row(
          children: [
            const Text(
              'كميات إضافية (اختياري)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF444444),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_circle_outline_rounded,
                  size: 16, color: AppColors.primary),
              label: const Text(
                'إضافة كمية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),

        // ── لا وحدات ──
        if (_units.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Text(
              'لا توجد كميات إضافية — المنتج سيُباع بالسعر الافتراضي فقط',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),

        // ── قائمة الوحدات ──
        ..._units.asMap().entries.map((e) {
          final i = e.key;
          final unit = e.value;
          final profit = (unit.costPrice != null && unit.costPrice! > 0)
              ? unit.price - unit.costPrice!
              : 0.0;

          return Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                if (unit.imageUrl != null && unit.imageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      unit.imageUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.productName != null &&
                                widget.productName!.trim().isNotEmpty
                            ? '${widget.productName!.trim()} - ${unit.label}'
                            : unit.label,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${unit.price.toStringAsFixed(0)} ر.ي'
                        '${profit > 0 ? " (ربح ${profit.toStringAsFixed(0)} ر.ي)" : ""}'
                        '${unit.sizeMl != null ? ' • ${unit.sizeMl!.toStringAsFixed(0)} مل' : ''}'
                        '${unit.qty > 1 ? ' • ${unit.qty} حبة' : ''}',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: profit > 0 ? Colors.teal : Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _edit(i),
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.primary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _remove(i),
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── حوار إضافة/تعديل وحدة (محصن من تسريب الذاكرة بـ StatefulWidget) ──
Future<ProductUnit?> _showUnitDialog(
  BuildContext context, {
  ProductUnit? existing,
}) {
  return showModalBottomSheet<ProductUnit>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UnitEditModalSheet(existing: existing),
  );
}

class _UnitEditModalSheet extends StatefulWidget {
  final ProductUnit? existing;
  const _UnitEditModalSheet({this.existing});

  @override
  State<_UnitEditModalSheet> createState() => _UnitEditModalSheetState();
}

class _UnitEditModalSheetState extends State<_UnitEditModalSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _prodDateCtrl;
  late final TextEditingController _expDateCtrl;

  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _removeOldImage = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _labelCtrl = TextEditingController(text: ex?.label ?? '');
    _priceCtrl = TextEditingController(
        text: ex != null ? ex.price.toStringAsFixed(0) : '');
    _costCtrl = TextEditingController(
        text: ex?.costPrice != null ? ex!.costPrice!.toStringAsFixed(0) : '');
    _qtyCtrl = TextEditingController(text: ex != null ? '${ex.qty}' : '1');
    _sizeCtrl = TextEditingController(
        text: ex?.sizeMl != null ? ex!.sizeMl!.toStringAsFixed(0) : '');
    _prodDateCtrl = TextEditingController(
        text: ex?.productionDate != null ? _fmtDate(ex!.productionDate!) : '');
    _expDateCtrl = TextEditingController(
        text: ex?.expiryDate != null ? _fmtDate(ex!.expiryDate!) : '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _qtyCtrl.dispose();
    _sizeCtrl.dispose();
    _prodDateCtrl.dispose();
    _expDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    try {
      final result = await pickCatalogImage();
      if (result.$1 == null || result.$2 == null) return;
      setState(() {
        _selectedImage = result.$1;
        _selectedImageBytes = result.$2;
        _removeOldImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل اختيار الصورة: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _saveUnit() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('عدد الحبات يجب أن يكون أكبر من صفر',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    if (_prodDateCtrl.text.trim().isNotEmpty &&
        DateTime.tryParse(_prodDateCtrl.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('صيغة تاريخ الإنتاج غير صحيحة',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (_expDateCtrl.text.trim().isNotEmpty &&
        DateTime.tryParse(_expDateCtrl.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('صيغة تاريخ الانتهاء غير صحيحة',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      String? imageUrl = widget.existing?.imageUrl;

      if (_removeOldImage) {
        // لا يتم حذف الصورة فوراً من السيرفر لتفادي فقدانها إذا ألغى الأدمن تعديل المنتج قبل الحفظ
        imageUrl = null;
      }

      if (_selectedImage != null) {
        imageUrl = await uploadCatalogImage(_selectedImage!);
        if (imageUrl == null || imageUrl.trim().isEmpty) {
          throw Exception('تعذر رفع صورة الكمية');
        }
      }

      if (!mounted) return;

      Navigator.pop(
        context,
        ProductUnit(
          label: _labelCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
          costPrice: double.tryParse(_costCtrl.text.trim()) ?? 0,
          qty: qty,
          sizeMl: double.tryParse(_sizeCtrl.text.trim()),
          imageUrl: imageUrl,
          productionDate: _prodDateCtrl.text.trim().isEmpty
              ? null
              : DateTime.tryParse(_prodDateCtrl.text.trim()),
          expiryDate: _expDateCtrl.text.trim().isEmpty
              ? null
              : DateTime.tryParse(_expDateCtrl.text.trim()),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل حفظ الكمية: $e',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Widget _imagePreview() {
    if (_selectedImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_selectedImageBytes!,
            width: 64, height: 64, fit: BoxFit.cover),
      );
    }
    if (!_removeOldImage &&
        widget.existing?.imageUrl != null &&
        widget.existing!.imageUrl!.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          widget.existing!.imageUrl!,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
              color: Colors.grey, size: 30),
        ),
      );
    }
    return const Icon(Icons.add_photo_alternate_rounded,
        color: AppColors.primary, size: 30);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10)),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.existing == null
                            ? 'إضافة كمية جديدة'
                            : 'تعديل الكمية',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _saving ? null : _chooseImage,
                        child: Container(
                          height: 82,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE6E9ED)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _imagePreview(),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'صورة الكمية من المعرض (اختياري)\nPNG أو JPG — سيتم ضغطها تلقائياً',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      color: Colors.grey,
                                      height: 1.6),
                                ),
                              ),
                              if (_selectedImageBytes != null ||
                                  widget.existing?.imageUrl != null)
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                            _selectedImage = null;
                                            _selectedImageBytes = null;
                                            _removeOldImage = true;
                                          }),
                                  icon: const Icon(Icons.close_rounded,
                                      color: Colors.red, size: 20),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _labelCtrl,
                        textDirection: TextDirection.rtl,
                        decoration: _dec(
                            'اسم الكمية، مثل: حبة، نصف كرتون، ربع كرتون *'),
                        style: const TextStyle(fontFamily: 'Cairo'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'اسم الكمية مطلوب'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              textDirection: TextDirection.rtl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'))
                              ],
                              decoration: _dec('سعر البيع ر.ي *'),
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 13),
                              validator: (v) {
                                final p = double.tryParse(v?.trim() ?? '');
                                return (p == null || p < 0)
                                    ? 'أدخل سعراً صحيحاً'
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _costCtrl,
                              textDirection: TextDirection.rtl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'))
                              ],
                              decoration: _dec('سعر الشراء 🔒'),
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _qtyCtrl,
                              textDirection: TextDirection.rtl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _dec('عدد الحبات الأساسية *'),
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 13),
                              validator: (v) {
                                final q = int.tryParse(v?.trim() ?? '');
                                return (q == null || q <= 0)
                                    ? 'أدخل عدد الحبات'
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _sizeCtrl,
                              textDirection: TextDirection.rtl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: _dec('الحجم بالمل'),
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _UnitManualDateField(
                              ctrl: _prodDateCtrl,
                              hint: 'إنتاج: 2026-05-15',
                              icon: Icons.calendar_today_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _UnitManualDateField(
                              ctrl: _expDateCtrl,
                              hint: 'انتهاء: 2027-05-15',
                              icon: Icons.event_busy_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveUnit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.save_rounded, size: 19),
                          label: Text(_saving ? 'جاري الحفظ...' : 'حفظ الكمية',
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── حقل إدخال التاريخ اليدوي المباشر والسريع ──
class _UnitManualDateField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;

  const _UnitManualDateField({
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
        _UnitDateInputFormatter(),
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
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
