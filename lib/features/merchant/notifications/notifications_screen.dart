import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/local_storage.dart';
import '../../../../core/services/realtime_hub.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'package:go_router/go_router.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    _markAllRead();
  }

  Future<void> _markAllRead() async {
    final uid = AppStorage.userId ?? '';
    if (uid.isEmpty) return;
    await ref.read(realtimeNotifsProvider.notifier).markAllRead(uid);
  }

  void _handleBack(BuildContext context) {
    try {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return;
      }
    } catch (_) {}

    if (AppStorage.hasAdminAccess) {
      context.go('/admin');
    } else if (AppStorage.isDriver) {
      context.go('/driver');
    } else {
      context.go('/merchant');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifs = ref.watch(realtimeNotifsProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: context.bgPage,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ──
              Container(
                color: context.bgHeader,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _handleBack(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: context.bgPage,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'الإشعارات',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 17,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Icon(Icons.notifications_rounded,
                        color: AppColors.primary, size: 22),
                  ],
                ),
              ),

              // ── القائمة ──
              Expanded(
                child: notifs.isEmpty
                    ? _EmptyNotif()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: notifs.length,
                        itemBuilder: (_, i) => _NotifCard(data: notifs[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════
class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _NotifCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title']?.toString() ?? 'إشعار';
    final body = data['body']?.toString() ?? '';
    final isRead = data['is_read'] == true;
    final createdAt = data['created_at'] != null
        ? (data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.tryParse(data['created_at'].toString()))
        : null;

    const color = AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRead ? context.bgCard : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead
              ? Colors.grey.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.notifications_rounded, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight:
                                isRead ? FontWeight.w600 : FontWeight.w800)),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                ]),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: context.textSecondary,
                          height: 1.5)),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(_formatTime(createdAt),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: context.textHint)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ════════════════════════════════════════
class _EmptyNotif extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_off_outlined,
                size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('لا توجد إشعارات',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('ستظهر هنا إشعارات الطلبات',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: context.textSecondary)),
        ],
      ),
    );
  }
}
