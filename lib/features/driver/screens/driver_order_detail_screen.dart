// ==================================================
// FILE: lib/features/driver/screens/driver_order_detail_screen.dart
// ==================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/widgets/app_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class DriverOrderDetailScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final Future<bool> Function(String, String, String) onAction;

  const DriverOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.data,
    required this.onAction,
  });

  @override
  State<DriverOrderDetailScreen> createState() =>
      _DriverOrderDetailScreenState();
}

class _DriverOrderDetailScreenState extends State<DriverOrderDetailScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loadingItems = true;
  bool _isSubmittingAction = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('order_items')
          .where('order_id', isEqualTo: widget.orderId)
          .get();
      if (!mounted) return;
      setState(() {
        _items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _loadingItems = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final merchantName =
        d['merchant_name'] ?? d['customer_name'] ?? 'غير معروف';
    final storeName = d['store_name'] as String?;
    final phone = (d['phone_number'] ?? d['contact']) as String?;
    final address = (d['delivery_address'] ?? d['store_name']) as String?;
    final lat = (d['latitude'] as num?)?.toDouble();
    final lng = (d['longitude'] as num?)?.toDouble();
    final notes = d['notes'] as String?;
    final total = (d['total_amount'] as num?)?.toDouble() ??
        (d['total'] as num?)?.toDouble() ??
        0.0;
    final status = d['status'] as String? ?? '';
    final orderNum = d['order_number'] ?? d['invoice_number'] ?? '';
    final paymentMethod = d['payment_method'] as String? ?? 'cash';
    final isConfirmed = status == 'confirmed';

    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: context.bgHeader,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: context.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'تفاصيل الطلب',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary),
            ),
            if (orderNum.isNotEmpty)
              Text(
                '#$orderNum',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          if (orderNum.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded,
                  color: AppColors.primary, size: 20),
              tooltip: 'نسخ رقم الطلب',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: orderNum.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم نسخ رقم الطلب',
                        style: TextStyle(fontFamily: 'Cairo')),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── بطاقة الحالة ──
            _StatusBanner(isConfirmed: isConfirmed),

            const SizedBox(height: 16),

            // ── بطاقة العميل ──
            _InfoCard(
              title: 'معلومات العميل',
              icon: Icons.store_rounded,
              iconColor: AppColors.primary,
              children: [
                _InfoRow(label: 'الاسم', value: merchantName),
                if (storeName != null)
                  _InfoRow(label: 'المتجر', value: storeName),
                if (phone != null)
                  _InfoRow(
                    label: 'الهاتف',
                    value: phone,
                    trailing: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: phone));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ الرقم',
                                style: TextStyle(fontFamily: 'Cairo')),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded,
                                size: 12, color: AppColors.primary),
                            SizedBox(width: 3),
                            Text('نسخ',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ── بطاقة التوصيل ──
            _InfoCard(
              title: 'معلومات التوصيل',
              icon: Icons.location_on_rounded,
              iconColor: Colors.orange,
              children: [
                if (address != null || (lat != null && lng != null))
                  _MapButton(
                    address: address,
                    lat: lat,
                    lng: lng,
                    merchantName: storeName ?? merchantName,
                  ),
                _InfoRow(
                  label: 'طريقة الدفع',
                  value: paymentMethod == 'cash' ? '💵 كاش' : '💳 تحويل',
                ),
                _InfoRow(
                  label: 'إجمالي الطلب',
                  value: '${total.toStringAsFixed(0)} ر.ي',
                  valueStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),

            // ── ملاحظات ──
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_rounded,
                        color: Colors.amber, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ملاحظات العميل',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFD97706))),
                          const SizedBox(height: 4),
                          Text(notes,
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: Color(0xFF92400E),
                                  height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── قائمة الأصناف ──
            _InfoCard(
              title: 'الأصناف المطلوبة',
              icon: Icons.inventory_2_rounded,
              iconColor: Colors.blue,
              children: _loadingItems
                  ? [
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        ),
                      )
                    ]
                  : _items.isEmpty
                      ? [
                          const _InfoRow(
                              label: 'الأصناف', value: 'لا توجد بيانات')
                        ]
                      : _items.map((item) => _ItemRow(item: item)).toList(),
            ),
          ],
        ),
      ),

      // ── زر الإجراء الثابت ──
      bottomNavigationBar: (status == 'delivered' || status == 'cancelled')
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              decoration: BoxDecoration(
                color: context.bgCard,
                boxShadow: [
                  BoxShadow(
                    color: context.shadowColor,
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isSubmittingAction
                      ? null
                      : () async {
                          setState(() => _isSubmittingAction = true);
                          try {
                            final success = await widget.onAction(
                              widget.orderId,
                              isConfirmed ? 'pick_up' : 'deliver',
                              merchantName,
                            );
                            if (success && context.mounted) {
                              Navigator.pop(context);
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isSubmittingAction = false);
                            }
                          }
                        },
                  icon: Icon(
                    isConfirmed
                        ? Icons.inventory_rounded
                        : Icons.check_circle_rounded,
                    size: 20,
                  ),
                  label: Text(
                    isConfirmed
                        ? 'استلمت من المستودع 📦'
                        : 'تم التسليم للعميل ✅',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isConfirmed ? Colors.blue : AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
    );
  }
}

// ══════════════════════════════════════════
// ويدجت شريط الحالة
// ══════════════════════════════════════════
class _StatusBanner extends StatelessWidget {
  final bool isConfirmed;
  const _StatusBanner({required this.isConfirmed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isConfirmed
            ? Colors.blue.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConfirmed
              ? Colors.blue.withValues(alpha: 0.25)
              : AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConfirmed
                ? Icons.inventory_2_rounded
                : Icons.local_shipping_rounded,
            size: 20,
            color: isConfirmed ? Colors.blue : AppColors.primary,
          ),
          const SizedBox(width: 10),
          Text(
            isConfirmed
                ? 'الطلب جاهز في المستودع — بانتظار استلامك'
                : 'الطلب معك الآن — بانتظار التسليم للعميل',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isConfirmed ? Colors.blue : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// بطاقة معلومات
// ══════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary),
                ),
              ],
            ),
          ),
          Divider(
              height: 1, indent: 16, endIndent: 16, color: context.borderColor),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// زر فتح الخريطة الموحدة للسائق
// ══════════════════════════════════════════
class _MapButton extends StatelessWidget {
  final String? address;
  final double? lat;
  final double? lng;
  final String merchantName;

  const _MapButton({
    this.address,
    this.lat,
    this.lng,
    required this.merchantName,
  });

  void _showUnifiedMap(BuildContext context) {
    final location = (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'موقع $merchantName',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppMap(
                initialLocation: location,
                defaultCenter: location ?? const LatLng(15.3694, 44.1910),
                initialZoom: 16.5,
                title: 'موقع العميل',
                markerLabel: merchantName,
                allowPick: false,
                showSearch: true,
                showCurrentLocation: true,
              ),
            ),
            // خيار إضافي للملاحة الخارجية إن أراد السائق التوجيه الصوتي
            if (location != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _launchExternalNavigation(context),
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text(
                      'الملاحة عبر تطبيق الخرائط الخارجي (GPS)',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchExternalNavigation(BuildContext context) async {
    final String urlString;
    if (lat != null && lng != null) {
      final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
      urlString = isIOS ? 'maps://?q=$lat,$lng' : 'geo:$lat,$lng?q=$lat,$lng';
    } else if (address != null && address!.isNotEmpty) {
      final encoded = Uri.encodeComponent(address!);
      final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
      urlString = isIOS ? 'maps://?q=$encoded' : 'geo:0,0?q=$encoded';
    } else {
      return;
    }

    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final queryParam =
            lat != null && lng != null ? '$lat,$lng' : (address ?? '');
        final fallbackUrl = Uri.https('www.google.com', '/maps/search/',
            {'api': '1', 'query': queryParam});
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'العنوان',
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          if (address != null && address!.isNotEmpty)
            Text(
              address!,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: Color(0xFF333333),
                height: 1.6,
              ),
            ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showUnifiedMap(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    width: 1.2),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'عرض موقع التوصيل على الخريطة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// صف معلومة
// ══════════════════════════════════════════
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  final TextStyle? valueStyle;

  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: Color(0xFF888888),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: valueStyle ??
                  const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
              textAlign: TextAlign.end,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════
// صف الصنف
// ══════════════════════════════════════════
class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['product_name'] ?? item['name'] ?? 'صنف';
    final qty = (item['quantity'] as num?)?.toInt() ?? 0;
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final total = qty * price;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary)),
                Text('$qty كرتون × ${price.toStringAsFixed(0)} ر.ي',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: context.textSecondary)),
              ],
            ),
          ),
          Text(
            '${total.toStringAsFixed(0)} ر.ي',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
