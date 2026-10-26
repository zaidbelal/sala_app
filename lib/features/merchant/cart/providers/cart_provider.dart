import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/models/product_unit.dart';
import '../models/cart_item_model.dart';
import '../../products/services/products_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CartNotifier extends StateNotifier<Map<String, CartItem>> {
  CartNotifier() : super({}) {
    _load();
  }

  static String get _key {
    final uid = AppStorage.userId ?? 'guest';
    return 'sala_cart_v2_$uid';
  }

  SharedPreferences? prefs;
  Timer? _saveDebounce;
  static const int _maxQuantity = 999;
  int flushEpoch = 0;
  Future<File?> get _cartFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_key.json');
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final file = await _cartFile;
      if (file == null || !await file.exists()) return;

      final raw = await file.readAsString();
      if (raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = map.map(
        (k, v) => MapEntry(k, CartItem.fromJson(v as Map<String, dynamic>)),
      );
      final merged = Map<String, CartItem>.from(loaded);
      state.forEach((key, value) {
        merged[key] = value;
      });
      state = merged;
    } catch (e, st) {
      if (kDebugMode) debugPrint('❌ CartNotifier._load failed: $e\n$st');
    }
  }

  Future<void> _cartSaveChain = Future.value();

  void _save() {
    // 🔒 جدولة تسلسلية حتمية (Sequential Mutex Queue) تضمن حفظ أحدث حالة دائماً بدون سباق
    _cartSaveChain =
        _cartSaveChain.then((_) => _executeSave()).catchError((_) {});
  }

  Future<void> forceSave() async {
    _cartSaveChain =
        _cartSaveChain.then((_) => _executeSave()).catchError((_) {});
    return _cartSaveChain;
  }

  Future<void> _executeSave() async {
    if (kIsWeb) return;
    if (!AppStorage.isLoggedIn || AppStorage.userId == null) return;

    try {
      final file = await _cartFile;
      if (file == null) return;

      // أخذ لقطة فورية للحالة الحالية داخل القفل
      final currentState = state;
      if (currentState.isEmpty) {
        if (await file.exists()) await file.delete().catchError((_) => file);
        return;
      }

      final dataMap = currentState.map((k, v) => MapEntry(k, v.toJson()));
      final jsonString = jsonEncode(dataMap);

      final nonce = DateTime.now().microsecondsSinceEpoch;
      final tempFile = File('${file.path}_$nonce.tmp');
      await tempFile.writeAsString(jsonString, flush: true);

      // استبدال ذري بدون حذف
      try {
        await tempFile.rename(file.path);
      } catch (_) {
        await tempFile.copy(file.path);
        await tempFile.delete().catchError((_) => tempFile);
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('❌ Cart Sequential Save Error: $e\n$st');
    }
  }

  @override
  void dispose() {
    flushEpoch++;
    _saveDebounce?.cancel();
    if (state.isNotEmpty && !kIsWeb) {
      // 🔒 كتابة تزامنية فورية متزامنة تضمن ثبات البيانات قبل تحرير الموفر والعملية
      try {
        final uid = AppStorage.userId ?? 'guest';
        if (AppStorage.isLoggedIn && AppStorage.userId != null) {
          final dataMap = state.map((k, v) => MapEntry(k, v.toJson()));
          final jsonString = jsonEncode(dataMap);
          AppStorage.setString('sala_cart_backup_$uid', jsonString);
        }
      } catch (_) {}
    }
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
    _saveDebounce?.cancel();
    state = {};
    await forceSave();
  }

  void clear() {
    _saveDebounce?.cancel();
    state = {};
    unawaited(forceSave());
  }

  /// استعادة السلة مباشرة إلى الذاكرة وملف التخزين عند فشل إرسال طلب أوفلاين
  Future<void> restoreCart(Map<String, dynamic> cartMap) async {
    final loaded = cartMap.map(
      (k, v) => MapEntry(k, CartItem.fromJson(v as Map<String, dynamic>)),
    );
    state = Map<String, CartItem>.from(loaded);
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
