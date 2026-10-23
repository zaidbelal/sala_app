import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_cache.dart';

class DeltaSyncService {
  DeltaSyncService._();
  static final DeltaSyncService instance = DeltaSyncService._();
  final _db = FirebaseFirestore.instance;

  static const String _kLastProductsSyncKey = 'delta_sync_products_ts';
  static const String _kLastCategoriesSyncKey = 'delta_sync_categories_ts';

  /// مزامنة المنتجات التي تم تعديلها أو إضافتها فقط منذ آخر عملية مزامنة ناجحة
  Future<bool> syncProductsDelta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncInt = prefs.getInt(_kLastProductsSyncKey);
      var currentCached = AppCache.instance.getProducts() ?? [];
// إذا كان الكاش فارغاً تماماً نقوم بجلب أولي كامل على دفعات لضمان عدم ضياع أي منتج
      if (currentCached.isEmpty || lastSyncInt == null) {
        final List<Map<String, dynamic>> allInitial = [];
        DocumentSnapshot? lastDoc;
        bool hasMoreInitial = true;
        DateTime? maxUpdatedTs;

        while (hasMoreInitial) {
          Query<Map<String, dynamic>> initialQuery = _db
              .collection('products')
              .orderBy(FieldPath.documentId)
              .limit(250);

          if (lastDoc != null) {
            initialQuery = initialQuery.startAfterDocument(lastDoc);
          }

          final initialSnap =
              await initialQuery.get(const GetOptions(source: Source.server));
          if (initialSnap.docs.isEmpty) {
            hasMoreInitial = false;
            break;
          }

          for (final d in initialSnap.docs) {
            final data = d.data();
            if (data['is_deleted'] != true && data['is_active'] != false) {
              allInitial.add({'id': d.id, ...data});
            }
            final rawTs = data['updated_at'];
            if (rawTs is Timestamp) {
              final date = rawTs.toDate();
              if (maxUpdatedTs == null || date.isAfter(maxUpdatedTs)) {
                maxUpdatedTs = date;
              }
            }
          }

          lastDoc = initialSnap.docs.last;
          hasMoreInitial = initialSnap.docs.length == 250;
        }

        if (allInitial.isNotEmpty) {
          await AppCache.instance.setProducts(allInitial);
          final commitTs = maxUpdatedTs ?? DateTime.now();
          await prefs.setInt(
              _kLastProductsSyncKey, commitTs.microsecondsSinceEpoch);
          return true;
        }
        return false;
      }
      DateTime lastSyncDate = DateTime.fromMicrosecondsSinceEpoch(lastSyncInt);
      bool anySynced = false;
      bool hasMore = true;
      DocumentSnapshot? lastVisibleDoc;
      DateTime? latestTimestampToCommit;

      while (hasMore) {
        Query<Map<String, dynamic>> query =
            _db.collection('products').orderBy('updated_at', descending: false);

        query = query.where(
          'updated_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(lastSyncDate),
        );
        if (lastVisibleDoc != null) {
          query = query.startAfterDocument(lastVisibleDoc);
        }
        final snapshot =
            await query.limit(100).get(const GetOptions(source: Source.server));
        if (snapshot.docs.isEmpty) {
          hasMore = false;
          break;
        }

        anySynced = true;
        final modifiedMap = <String, Map<String, dynamic>>{
          for (final doc in snapshot.docs)
            doc.id: {'id': doc.id, ...doc.data()},
        };

        final mergedProducts = <String, Map<String, dynamic>>{
          for (final p in currentCached) p['id'].toString(): p,
        };

        for (final entry in modifiedMap.entries) {
          if (entry.value['is_deleted'] == true ||
              entry.value['is_active'] == false) {
            mergedProducts.remove(entry.key);
          } else {
            mergedProducts[entry.key] = entry.value;
          }
        }

        currentCached = mergedProducts.values.toList();
        final lastDoc = snapshot.docs.last;
        lastVisibleDoc = lastDoc;

        final rawTs = lastDoc.data()['updated_at'];
        if (rawTs is Timestamp) {
          latestTimestampToCommit = rawTs.toDate();
        }
        hasMore = snapshot.docs.length == 100;
      }

      // ✅ حفظ الكاش أولاً في القرص، وفور نجاحه فقط نحفظ نقطة الختم الزمني لضمان عدم ضياع المنتجات
      if (anySynced) {
        await AppCache.instance.setProducts(currentCached);
        if (latestTimestampToCommit != null) {
          await prefs.setInt(_kLastProductsSyncKey,
              latestTimestampToCommit.microsecondsSinceEpoch);
        }
      }

      return anySynced;
    } catch (e) {
      if (kDebugMode) debugPrint('Delta sync failed: $e');
      return false;
    }
  }

  /// مزامنة الأصناف بالفروقات
  Future<bool> syncCategoriesDelta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncInt = prefs.getInt(_kLastCategoriesSyncKey);
      var currentCached = AppCache.instance.getCategories() ?? [];

      DateTime? lastSyncDate = (lastSyncInt != null && currentCached.isNotEmpty)
          ? DateTime.fromMicrosecondsSinceEpoch(lastSyncInt)
          : null;
      bool anySynced = false;
      bool hasMore = true;
      DocumentSnapshot? lastVisibleDoc;
      DateTime? latestCatTimestampToCommit;

      while (hasMore) {
        Query<Map<String, dynamic>> query = _db
            .collection('categories')
            .orderBy('updated_at', descending: false);

        if (lastSyncDate != null) {
          query = query.where(
            'updated_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(lastSyncDate),
          );
        }
        if (lastVisibleDoc != null) {
          query = query.startAfterDocument(lastVisibleDoc);
        }
        final snapshot =
            await query.limit(50).get(const GetOptions(source: Source.server));
        if (snapshot.docs.isEmpty) {
          hasMore = false;
          break;
        }

        anySynced = true;
        final modifiedMap = <String, Map<String, dynamic>>{
          for (final doc in snapshot.docs)
            doc.id: {'id': doc.id, ...doc.data()},
        };

        final mergedCategories = <String, Map<String, dynamic>>{
          for (final c in currentCached) c['id'].toString(): c,
        };
        for (final entry in modifiedMap.entries) {
          if (entry.value['is_deleted'] == true ||
              entry.value['is_active'] == false) {
            mergedCategories.remove(entry.key);
          } else {
            mergedCategories[entry.key] = entry.value;
          }
        }

        currentCached = mergedCategories.values.toList();

        final lastDoc = snapshot.docs.last;
        lastVisibleDoc = lastDoc;
        final rawTs = lastDoc.data()['updated_at'];
        if (rawTs is Timestamp) {
          latestCatTimestampToCommit = rawTs.toDate();
        }
        hasMore = snapshot.docs.length == 50;
      }

      // ✅ الحفظ الذري: القرص أولاً وفور نجاحه فقط يتم تحديث الختم الزمني
      if (anySynced) {
        await AppCache.instance.setCategories(currentCached);
        if (latestCatTimestampToCommit != null) {
          await prefs.setInt(
            _kLastCategoriesSyncKey,
            latestCatTimestampToCommit.microsecondsSinceEpoch,
          );
        }
      }

      return anySynced;
    } catch (_) {
      return false;
    }
  }
}
