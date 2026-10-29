import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/models/product_unit.dart';
import '../models/cart_item_model.dart';
import '../../products/services/products_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CartNotifier extends StateNotifier<Map<String, CartItem>> {
  static int _revisionCounter = 0;

  CartNotifier() : super({}) {
    _loadFuture = _load();
  }

  late final Future<void> _loadFuture;

  static String get _key {
    final uid = AppStorage.userId ?? 'guest';
    return 'sala_cart_v2_$uid';
  }

  SharedPreferences? prefs;
  static const int _maxQuantity = 999;
  int flushEpoch = 0;
  String? _cartRevision;
  bool _ignoreLoadedCart = false;
  String get cartRevision => _cartRevision ??= _newCartRevision();

  String _newCartRevision() =>
      '${DateTime.now().microsecondsSinceEpoch}_${++_revisionCounter}';

  // ── طبقة المستودع المعزولة (Cart Storage Repository) ──
  final _repository = const CartStorageRepository();
  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final revision = await _repository.readRevision(_key);
      if (revision != null) _cartRevision = revision;
      _cartRevision ??= _newCartRevision();

      var loaded = await _repository.readCart(_key);

      // 🔒 تحفة الترحيل التلقائي: إذا سجل التاجر دخوله وسلته فارغة، ننقل بضائع سلة الزائر السابقة لحسابه فوراً
      final currentUid = AppStorage.userId;
      if ((loaded == null || loaded.isEmpty) &&
          currentUid != null &&
          currentUid.isNotEmpty) {
        const guestKey = 'sala_cart_v2_guest';
        final guestCart = await _repository.readCart(guestKey);
        if (guestCart != null && guestCart.isNotEmpty) {
          loaded = guestCart;
          // ترحيل السلة وحفظها باسم التاجر المسجل وتطهير سلة الزائر
          await _repository.saveCart(
            key: _key,
            revision: _cartRevision!,
            items: guestCart,
          );
          await _repository.deleteCart(guestKey);
        }
      }

      if (loaded == null || loaded.isEmpty) return;

      final merged = _ignoreLoadedCart
          ? <String, CartItem>{}
          : Map<String, CartItem>.from(loaded);
      state.forEach((key, value) {
        merged[key] = value;
      });
      _ignoreLoadedCart = false;
      state = merged;
    } catch (e, st) {
      if (kDebugMode) debugPrint('❌ CartNotifier._load failed: $e\n$st');
    }
  }

  Future<void> _cartSaveChain = Future.value();

  void _save() {
    final revision = _newCartRevision();
    _cartRevision = revision;
    final itemsSnapshot = Map<String, CartItem>.unmodifiable(state);

    _cartSaveChain = _cartSaveChain.then((_) async {
      await _loadFuture;
      await _repository.saveCart(
        key: _key,
        revision: revision,
        items: itemsSnapshot,
      );
    }).catchError((Object error, StackTrace stackTrace) {
      if (kDebugMode)
        debugPrint('Cart persistence failed: $error\n$stackTrace');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(error, stackTrace, reason: 'Cart persistence failed');
      }
    });
  }

  Future<void> forceSave() async {
    await _loadFuture;
    return _cartSaveChain;
  }

  @override
  void dispose() {
    flushEpoch++;
    super.dispose();
  }

  /// تبديل وحدة/كمية الصنف في السلة مع الحفاظ التام على عدد العبوات المطلوبة دون تقريب عشوائي
  void changeItemUnit(CartItem oldItem, ProductUnit newUnit) {
    final oldKey = oldItem.cartKey;
    final newItem = CartItem(
      product: oldItem.product,
      quantity: oldItem.quantity.clamp(1, _maxQuantity),
      selectedUnit: newUnit,
    );
    final newKey = newItem.cartKey;

    if (oldKey == newKey) return;

    final newState = Map<String, CartItem>.from(state);
    newState.remove(oldKey);

    if (newState.containsKey(newKey)) {
      final existing = newState[newKey]!;
      newState[newKey] = existing.copyWith(
        quantity: (existing.quantity + oldItem.quantity).clamp(1, _maxQuantity),
      );
    } else {
      newState[newKey] = newItem;
    }
    state = newState;
    _save();
  }

  void addItem(ProductModel product, int quantity, {ProductUnit? unit}) {
    if (quantity <= 0) return;
    final item = CartItem(
      product: product,
      quantity: quantity,
      selectedUnit: unit,
    );
    final key = item.cartKey;
    final existing = state[key];
    final currentQty = existing?.quantity ?? 0;
    final newQty = (currentQty + quantity).clamp(1, _maxQuantity);

    state = {
      ...state,
      key: item.copyWith(quantity: newQty),
    };
    _save();
  }

  void setQuantity(CartItem item, int quantity) {
    final key = item.cartKey;
    if (quantity <= 0) {
      removeItem(key);
      return;
    }
    final existing = state[key] ?? item;
    state = {
      ...state,
      key: existing.copyWith(quantity: quantity.clamp(1, _maxQuantity)),
    };
    _save();
  }

  void removeItem(String cartKey) {
    if (!state.containsKey(cartKey)) return;
    final newState = Map<String, CartItem>.from(state)..remove(cartKey);
    state = newState;
    _save();
  }

  void incrementItem(CartItem item) {
    final key = item.cartKey;
    final existing = state[key];
    if (existing == null) {
      addItem(item.product, 1, unit: item.selectedUnit);
      return;
    }
    if (existing.quantity >= _maxQuantity) return;
    state = {
      ...state,
      key: existing.copyWith(quantity: existing.quantity + 1),
    };
    _save();
  }

  void decrementItem(CartItem item) {
    final key = item.cartKey;
    final existing = state[key];
    if (existing == null) return;
    if (existing.quantity <= 1) {
      removeItem(key);
      return;
    }
    state = {
      ...state,
      key: existing.copyWith(quantity: existing.quantity - 1),
    };
    _save();
  }

  Future<void> clearAsync() async {
    await _loadFuture;
    _ignoreLoadedCart = false;
    state = {};
    await forceSave();
  }

  Future<void> clearIfRevision(String expectedRevision) async {
    await _loadFuture;
    await _cartSaveChain;
    if (_cartRevision != expectedRevision) return;
    await clearAsync();
  }

  void clear() {
    _ignoreLoadedCart = true;
    state = {};
    _save();
  }

  /// استعادة السلة مباشرة إلى الذاكرة وملف التخزين عند فشل إرسال طلب أوفلاين
  Future<void> restoreCart(Map<String, dynamic> cartMap) async {
    await _loadFuture;
    final loaded = cartMap.map(
      (k, v) => MapEntry(k, CartItem.fromJson(v as Map<String, dynamic>)),
    );
    state = Map<String, CartItem>.from(loaded);
    _ignoreLoadedCart = false;
    _cartRevision = _newCartRevision();
    await forceSave();
  }

  int quantityOf(String cartKey) => state[cartKey]?.quantity ?? 0;
// ✅ دالة تحديث ومزامنة أسعار السلة لجميع الوحدات (مع حماية تامة ضد مسح المنتجات)
  bool validateAndUpdatePrices(
    List<Map<String, dynamic>> latestProducts, {
    Set<String>? queriedBatchIds,
  }) {
    if (state.isEmpty) return false;
    bool hasChanges = false;
    final Map<String, CartItem> resolvedMap = {};
    final returnedProductsMap = {
      for (final p in latestProducts) p['id']?.toString(): p
    };

    for (final entry in state.entries) {
      final item = entry.value;
      final productId = item.product.id;

      // إذا لم يكن المنتج ضمن الدفعة المفحوصة حالياً، نحتفظ به مؤقتاً
      if (queriedBatchIds != null && !queriedBatchIds.contains(productId)) {
        resolvedMap[entry.key] = item;
        continue;
      }

      final liveProductMap = returnedProductsMap[productId];

      // حذف فوري للصنف إذا حُذف المستند تماماً من السيرفر أو تم تعطيله/حذفه منطقياً
      if (liveProductMap == null ||
          liveProductMap.isEmpty ||
          liveProductMap['is_deleted'] == true ||
          liveProductMap['is_active'] == false) {
        hasChanges = true;
        continue;
      }
      final liveProduct = ProductModel.fromMap(liveProductMap);
      final currentLabel = item.selectedUnit?.label.trim() ?? 'كرتون';

      ProductUnit? matchingUnit = liveProduct.units
          .where((u) => u.label.trim() == currentLabel)
          .firstOrNull;

      if (matchingUnit == null && currentLabel == 'كرتون') {
        matchingUnit = ProductUnit(
          label: 'كرتون',
          qty: liveProduct.itemsPerCarton ?? 1,
          price: liveProduct.price,
          imageUrl: liveProduct.imageUrl,
          sizeMl: liveProduct.sizeMl,
        );
      }
// 🛡️ حماية مالية صارمة: إذا حُذفت أو عُدلت عبوة البيع التي اختارها التاجر سحابياً،
      // يُستبعد الصنف فوراً من السلسلة ليقوم التاجر بتحديد العبوة الجديدة بوعي تام
      if (matchingUnit == null) {
        hasChanges = true;
        continue;
      }

      if (matchingUnit.price != item.unitPrice ||
          liveProduct.price != item.product.price) {
        hasChanges = true;
      }

      final updatedItem = CartItem(
        product: liveProduct,
        quantity: item.quantity,
        selectedUnit: matchingUnit,
      );

      final targetKey = updatedItem.cartKey;
      if (resolvedMap.containsKey(targetKey)) {
        final existing = resolvedMap[targetKey]!;
        resolvedMap[targetKey] = existing.copyWith(
          quantity:
              (existing.quantity + updatedItem.quantity).clamp(1, _maxQuantity),
        );
        hasChanges = true;
      } else {
        resolvedMap[targetKey] = updatedItem;
      }
    }

    if (hasChanges || resolvedMap.length != state.length) {
      state = resolvedMap;
      _save();
      return true;
    }
    return false;
  }
}

/// عزل كامل لمسؤولية قراءة وكتابة السلة على القرص (Clean Architecture Layer)
class CartStorageRepository {
  const CartStorageRepository();

  Future<File?> _getFile(String name) async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  Future<String?> readRevision(String key) async {
    final file = await _getFile('$key.revision');
    if (file != null && await file.exists()) {
      final rev = (await file.readAsString()).trim();
      return rev.isNotEmpty ? rev : null;
    }
    return null;
  }

  Future<Map<String, CartItem>?> readCart(String key) async {
    final file = await _getFile('$key.json');
    String? raw;
    if (file != null && await file.exists()) {
      raw = await file.readAsString();
    }
    if (raw != null && raw.trim().isNotEmpty && raw.trim() != '{}') {
      try {
        return _decodeCart(raw);
      } catch (error) {
        final backupFile = File('${file!.path}.bak');
        if (await backupFile.exists()) {
          try {
            raw = await backupFile.readAsString();
            final recovered = _decodeCart(raw);
            try {
              await backupFile.copy(file.path);
            } catch (restoreError) {
              debugPrint('Cart backup recovery could not restore primary file: '
                  '$restoreError (original parse error: $error)');
            }
            return recovered;
          } catch (backupError) {
            debugPrint('Cart backup could not be decoded: $backupError');
          }
        }
        raw = null;
      }
    }

    if (raw == null || raw.trim().isEmpty || raw.trim() == '{}') {
      final uid = AppStorage.userId ?? 'guest';
      final fallback = AppStorage.getString('sala_cart_v2_$uid');
      if (fallback != null &&
          fallback.trim().isNotEmpty &&
          fallback.trim() != '{}') {
        raw = fallback;
      }
    }
    if (raw == null || raw.trim().isEmpty || raw.trim() == '{}') return null;

    return _decodeCart(raw);
  }

  Map<String, CartItem> _decodeCart(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map(
        (k, v) => MapEntry(k, CartItem.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> deleteCart(String key) async {
    if (kIsWeb) return;
    try {
      final file = await _getFile('$key.json');
      final revFile = await _getFile('$key.revision');
      final backupFile = await _getFile('$key.bak');
      if (file != null && await file.exists()) await file.delete();
      if (revFile != null && await revFile.exists()) await revFile.delete();
      if (backupFile != null && await backupFile.exists())
        await backupFile.delete();
      await AppStorage.remove(key);
    } catch (_) {}
  }

  Future<void> saveCart({
    required String key,
    required String revision,
    required Map<String, CartItem> items,
  }) async {
    // 🔒 تم رفع حظر الزائر: يُسمح بحفظ السلة دائماً على القرص سواء كان مسجلاً أو زائراً
    if (kIsWeb) return;
    final file = await _getFile('$key.json');
    final revFile = await _getFile('$key.revision');
    if (file == null || revFile == null) return;

    if (items.isEmpty) {
      if (await file.exists()) await file.delete();
      final backupFile = File('${file.path}.bak');
      if (await backupFile.exists()) await backupFile.delete();
      if (await revFile.exists()) await revFile.delete();
      await AppStorage.remove(key);
      return;
    }
    final jsonString = jsonEncode(items.map((k, v) => MapEntry(k, v.toJson())));
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final tempFile = File('${file.path}_$nonce.tmp');
    await tempFile.writeAsString(jsonString, flush: true);
    final backupFile = File('${file.path}.bak');
    if (await file.exists()) {
      try {
        jsonDecode(await file.readAsString());
        await file.copy(backupFile.path);
      } on FormatException {
        // Keep the previous known-good backup.
      }
    }

    try {
      await tempFile.rename(file.path);
    } catch (_) {
      await tempFile.copy(file.path);
      await tempFile.delete();
    }
    await revFile.writeAsString(revision, flush: true);
    await AppStorage.setString(key, jsonString);
  }
}

// مزودات السلة يجب أن تكون خارج الصنف CartNotifier.
final cartProvider = StateNotifierProvider<CartNotifier, Map<String, CartItem>>(
  (ref) => CartNotifier(),
);

final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).values.fold(0.0, (s, i) => s + i.total);
});

final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).values.fold(0, (s, i) => s + i.quantity);
});
