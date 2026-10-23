import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../services/admin_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final _notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(adminServiceProvider).getNotifications();
});

class AdminNotificationsTab extends ConsumerStatefulWidget {
  const AdminNotificationsTab({super.key});

  @override
  ConsumerState<AdminNotificationsTab> createState() =>
      _AdminNotificationsTabState();
}

class _AdminNotificationsTabState extends ConsumerState<AdminNotificationsTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);

    try {
      await ref.read(adminServiceProvider).sendNotification(
            title: _titleCtrl.text.trim(),
            body: _bodyCtrl.text.trim(),
          );

      if (mounted) {
        _titleCtrl.clear();
        _bodyCtrl.clear();
        ref.invalidate(_notificationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال الإشعار بنجاح ✅'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: StadiumBorder(),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الإرسال: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: const StadiumBorder(),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(_notificationsProvider);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── العنوان ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Text(
                'إرسال إشعار',
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),

          // ── نموذج الإرسال ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // ── عنوان الإشعار ──
                    TextField(
                      controller: _titleCtrl,
                      decoration: _inputDec('عنوان الإشعار'),
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 12),

                    // ── نص الإشعار ──
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 3,
                      decoration: _inputDec('نص الإشعار'),
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 16),

                    // ── زر الإرسال ──
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _sending ? null : _send,
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: _sending
                              ? const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send_rounded,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 10),
                                    Text(
                                      'إرسال لجميع التجار',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
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
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── عنوان الإشعارات السابقة ──
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'الإشعارات السابقة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF555555),
                ),
              ),
            ),
          ),

          // ── قائمة الإشعارات ──
          notificationsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            ),
            error: (_, __) => const SliverToBoxAdapter(
                child: Center(child: Text('فشل التحميل'))),
            data: (list) {
              if (list.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text('لم يُرسَل أي إشعار بعد',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.grey[400])),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final n = list[i];
                    final rawDate = n['created_at'];
                    final date = rawDate is Timestamp
                        ? rawDate.toDate()
                        : DateTime.tryParse(rawDate?.toString() ?? '');
                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.notifications_rounded,
                                color: AppColors.primary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n['title'] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  n['body'] ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (date != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${date.day}/${date.month}/${date.year} — ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: list.length,
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontFamily: 'Cairo', color: Color(0xFFAAAAAA)),
        filled: true,
        fillColor: const Color(0xFFF8FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}
