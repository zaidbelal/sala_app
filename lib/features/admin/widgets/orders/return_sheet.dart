import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../services/admin_service.dart';

class ReturnSheet extends StatefulWidget {
  final AdminOrder order;
  final AdminService service;
  final VoidCallback onDone;
  const ReturnSheet(
      {super.key,
      required this.order,
      required this.service,
      required this.onDone});

  @override
  State<ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<ReturnSheet> {
  List<Map<String, dynamic>> _items = [];
  final Map<int, int> _returnQty = {};
  final _reasonCtrl = TextEditingController();
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await widget.service.getOrderItems(widget.order.id);
    if (!mounted) return;
    setState(() {
      _items = items;
      for (var i = 0; i < items.length; i++) {
        _returnQty[i] = 0;
      }
      _loading = false;
    });
  }

  Future<void> _confirm() async {
    if (!_returnQty.values.any((q) => q > 0)) {
      _showSnack('حدد كمية ارجاع لمنتج واحد على الأقل', Colors.orange);
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      _showSnack('سبب الارجاع مطلوب', Colors.orange);
      return;
    }

    setState(() => _submitting = true);

    try {
      final returnItemsPayload = <Map<String, dynamic>>[];
      for (var i = 0; i < _items.length; i++) {
        final q = _returnQty[i] ?? 0;
        if (q > 0) {
          returnItemsPayload.add({
            'item_id': _items[i]['id']?.toString() ?? '',
            'quantity': q,
          });
        }
      }

      await widget.service.processReturn(
        widget.order.id,
        _reasonCtrl.text.trim(),
        returnItems: returnItemsPayload,
      );

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      // ── أغلق الشيت فقط (pop واحدة) ──
      Navigator.of(context).pop();

      // ── أشعر الشاشة الأم بالتحديث ──
      widget.onDone();

      // ── اشعار النجاح ──
      messenger.showSnackBar(
        SnackBar(
          content: const Text('تم تسجيل الارجاع بنجاح ✓',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack('فشل الإرسال: ${e.toString()}', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  bool get _hasSelection => _returnQty.values.any((q) => q > 0);
  int get _totalQty => _returnQty.values.fold(0, (s, q) => s + q);

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // المقبض
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),

          // العنوان
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.assignment_return_rounded,
                    color: Color(0xFFEA580C), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تسجيل ارجاع',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E))),
                      Text(order.storeName ?? order.merchantName,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.grey[500])),
                    ]),
              ),
              if (_hasSelection)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_totalQty كرتون',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFEA580C)),
                  ),
                ),
            ]),
          ),
          const Divider(height: 20),

          // المحتوى
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بيانات التاجر
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(children: [
                      _ReturnInfoRow(
                        icon: Icons.storefront_rounded,
                        label: 'البقالة',
                        value: order.storeName ?? order.merchantName,
                      ),
                      const Divider(height: 16),
                      _ReturnInfoRow(
                        icon: Icons.phone_rounded,
                        label: 'الهاتف',
                        value: order.phoneNumber ?? '—',
                        iconColor: AppColors.primary,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  // المنتجات
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: Row(children: [
                            Icon(Icons.inventory_2_rounded,
                                size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text('اختر المنتجات المرتجعة',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        const Divider(height: 1),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2)),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 12),
                            itemBuilder: (_, i) {
                              final item = _items[i];
                              final name =
                                  item['product_name']?.toString() ?? 'منتج';
                              final totalQty =
                                  (item['quantity'] as num?)?.toInt() ?? 0;
                              final alreadyReturned =
                                  (item['returned_quantity'] as num?)
                                          ?.toInt() ??
                                      0;
                              final maxQty = (totalQty - alreadyReturned)
                                  .clamp(0, totalQty);
                              final current = _returnQty[i] ?? 0;
                              return Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                      Text('الكمية: $maxQty كرتون',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: Colors.grey[500])),
                                    ],
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: current > 0
                                        ? const Color(0xFFFFF7ED)
                                        : const Color(0xFFF5F7FA),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: current > 0
                                            ? const Color(0xFFEA580C)
                                            : Colors.grey[300]!),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _CounterBtn(
                                          icon: Icons.remove,
                                          enabled: current > 0,
                                          onTap: () => setState(() =>
                                              _returnQty[i] = current - 1)),
                                      SizedBox(
                                        width: 34,
                                        child: Text('$current',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: current > 0
                                                    ? const Color(0xFFEA580C)
                                                    : Colors.grey[700])),
                                      ),
                                      _CounterBtn(
                                          icon: Icons.add,
                                          enabled: current < maxQty,
                                          onTap: () => setState(() =>
                                              _returnQty[i] = current + 1)),
                                    ],
                                  ),
                                ),
                              ]);
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // سبب الارجاع
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: TextField(
                      controller: _reasonCtrl,
                      maxLines: 3,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'سبب الارجاع (مطلوب) ...',
                        hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.grey[400]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // الأزرار
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: Color(0xFFDDDDDD)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إلغاء',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                color: Colors.grey,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed:
                            (_submitting || !_hasSelection) ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFFEA580C).withValues(alpha: 0.4),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                _hasSelection
                                    ? 'تأكيد ارجاع $_totalQty كرتون'
                                    : 'اختر كمية أولاً',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── صف معلومة ──
class _ReturnInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  const _ReturnInfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: iconColor ?? Colors.grey[400]),
      const SizedBox(width: 8),
      Text('$label: ',
          style: TextStyle(
              fontFamily: 'Cairo', fontSize: 12, color: Colors.grey[500])),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

// ── زر العداد ──
class _CounterBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _CounterBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon,
            size: 16,
            color: enabled ? const Color(0xFFEA580C) : Colors.grey[300]),
      ),
    );
  }
}
