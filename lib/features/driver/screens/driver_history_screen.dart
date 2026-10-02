import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sala/core/constants/app_colors.dart';
import 'package:sala/core/services/local_storage.dart';
import 'driver_order_detail_screen.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final driverId = AppStorage.userId ?? '';
      final snap = await _db
          .collection('orders')
          .where('driver_id', isEqualTo: driverId)
          .where('status', isEqualTo: 'delivered')
          .orderBy('created_at', descending: true)
          .limit(100)
          .get();
      if (mounted) {
        setState(() {
          _orders = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
            ..sort((a, b) {
              DateTime? parse(dynamic v) {
                if (v is Timestamp) return v.toDate();
                if (v is DateTime) return v;
                if (v is String) return DateTime.tryParse(v);
                return null;
              }

              final aTime = parse(a['delivered_at'] ?? a['created_at']);
              final bTime = parse(b['delivered_at'] ?? b['created_at']);
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        title: Text('سجل الرحلات المكتملة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: context.textPrimary)),
        backgroundColor: context.bgHeader,
        elevation: 0,
        centerTitle: true,
      ),
      body: _orders.isEmpty
          ? const Center(
              child: Text('لا يوجد سجل طلبات مكتملة بعد',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            )
          : RefreshIndicator(
              onRefresh: _loadHistory,
              color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (context, index) {
                  final data = _orders[index];
                  final merchantName =
                      data['merchant_name'] ?? data['customer_name'] ?? 'عميل';
                  final total = (data['total_amount'] as num?)?.toDouble() ??
                      (data['total'] as num?)?.toDouble() ??
                      0.0;
                  return Card(
                    color: context.bgCard,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: context.borderColor)),
                    child: ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverOrderDetailScreen(
                            orderId: data['id'] as String,
                            data: data,
                            onAction: (_, __, ___) async => true,
                          ),
                        ),
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8F5E9),
                        child:
                            Icon(Icons.check_rounded, color: AppColors.primary),
                      ),
                      title: Text(merchantName,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700)),
                      subtitle: Text('${total.toStringAsFixed(0)} ر.ي',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800)),
                      trailing:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
