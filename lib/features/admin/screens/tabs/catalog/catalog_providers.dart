import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 👈 هذا هو الاستيراد الذي كان مفقوداً
import '../../../services/admin_service.dart';

final adminCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final keepAliveLink = ref.keepAlive();
  Timer? timer;
  // تفريغ الذاكرة العشوائية (RAM) تلقائياً بعد 3 دقائق من عدم استخدام الأدمن للكتالوج
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(minutes: 3), () => keepAliveLink.close());
  });
  ref.onResume(() => timer?.cancel());

  return ref.watch(adminServiceProvider).getCategories();
});

final brandsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.keepAlive();
  return ref.watch(adminServiceProvider).getBrands();
});

final productsLoadingMoreProvider =
    StateProvider.autoDispose<bool>((ref) => false);

class AdminProductsPaginationNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  AdminProductsPaginationNotifier(this._ref)
      : super(const AsyncValue.loading()) {
    loadInitial();
  }

  Future<void> loadInitial({bool silent = false}) async {
    // عدم تدمير واجهة المستخدم بـ loading كامل إذا كانت البيانات موجودة مسبقاً
    if (!silent && (state.value == null || state.value!.isEmpty)) {
      state = const AsyncValue.loading();
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache));

      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length == 40;

      if (!mounted) return;

      final list = snap.docs
          .where((d) => d.data()['is_deleted'] != true)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      // الفرز في الذاكرة لتجنب التعليق ومشاكل الفهارس المركبة
      list.sort((a, b) =>
          (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));

      if (!mounted) return;
      state = AsyncValue.data(list);
    } catch (e, st) {
      if (!mounted) return;
      if (!silent) state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore ||
        _ref.read(productsLoadingMoreProvider) ||
        _lastDoc == null) {
      return;
    }
    _ref.read(productsLoadingMoreProvider.notifier).state = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .startAfterDocument(_lastDoc!)
          .limit(30)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length == 30;
      final current = state.value ?? [];
      final more = snap.docs
          .where((d) => d.data()['is_deleted'] != true)
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      final map = <String, Map<String, dynamic>>{
        for (final item in current) item['id'].toString(): item,
      };
      for (final item in more) {
        map[item['id'].toString()] = item;
      }

      final combined = map.values.toList();
      combined.sort((a, b) =>
          (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));

      if (!mounted) return;
      state = AsyncValue.data(combined);
    } finally {
      _ref.read(productsLoadingMoreProvider.notifier).state = false;
    }
  }
}

final adminProductsProvider = StateNotifierProvider.autoDispose<
    AdminProductsPaginationNotifier,
    AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final keepAliveLink = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(minutes: 5), () => keepAliveLink.close());
  });
  ref.onResume(() => timer?.cancel());

  return AdminProductsPaginationNotifier(ref);
});
