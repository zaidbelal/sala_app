import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sala/core/services/local_storage.dart';
import 'package:sala/core/models/product_unit.dart';
import '../models/cart_item_model.dart';
import '../../products/services/products_service.dart';

class CartNotifier extends StateNotifier<Map<String, CartItem>> {
  CartNotifier() : super({}) {
    _load();
  }

  static String get _key {
    final uid = AppStorage.userId ?? 'guest';
    return 'sala_cart_v2_$uid';
  }

  SharedPreferences? _prefs;
  Timer? _saveDebounce;
  static const int _maxQuantity = 999;
  int _flushEpoch = 0;

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw == null || raw.isEmpty) return;
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

  void _save() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), forceSave);
  }

  Future<void> forceSave() async {
    final currentEpoch = ++_flushEpoch;
    try {
      // منع الحفظ وإلغاء كتابة السلة للقرص إذا تم تسجيل الخروج أو مسح الحساب
      if (!AppStorage.isLoggedIn || AppStorage.userId == null) {
        return;
      }
      _prefs ??= await SharedPreferences.getInstance();
      if (state.isEmpty) {
        await _prefs!.remove(_key);
        return;
      }
      final dataMap = state.map((k, v) => MapEntry(k, v.toJson()));
      final jsonString = jsonEncode(dataMap);
      if (currentEpoch == _flushEpoch) {
        if (state.isEmpty) {
          await _prefs!.remove(_key);
        } else {
          await _prefs!.setString(_key, jsonString);
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('❌ CartNotifier._flush failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _flushEpoch++;
    _saveDebounce?.cancel();
    if (state.isNotEmpty) {
      unawaited(forceSave());
    }
    super.dispose();
  }

  /// تبديل وحدة/كمية الصنف في السلة مباشرة ودمج الكميات تلقائياً
  void changeItemUnit(CartItem oldItem, ProductUnit newUnit) {
    final oldKey = oldItem.cartKey;
    final newItem = CartItem(
      product: oldItem.product,
      quantity: oldItem.quantity,
      selectedUnit: newUnit,
    );
    final newKey = newItem.cartKey;

    if (oldKey == newKey) return;

    final newState = Map<String, CartItem>.from(state);
    newState.remove(oldKey);

    if (newState.containsKey(newKey)) {
      final existing = newState[newKey]!;
      newState[newKey] = existing.copyWith(
        // 🚀 لا نجمع الكميات إذا اختلفت الوحدة (كرتون وحبة) لمنع طلب كميات ضخمة جداً بالخطأ
        quantity: oldItem.quantity.clamp(1, _maxQuantity),
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

  void clear() {
    _saveDebounce?.cancel();
    state = {};
    unawaited(_prefs?.remove(_key));
  }

  int quantityOf(String cartKey) => state[cartKey]?.quantity ?? 0;
// ✅ دالة تحديث ومزامنة أسعار السلة لجميع الوحدات (مع حماية تامة ضد مسح المنتجات)
  bool validateAndUpdatePrices(List<Map<String, dynamic>> latestProducts) {
    if (state.isEmpty || latestProducts.isEmpty) return false;
    bool hasChanges = false;
    final Map<String, CartItem> resolvedMap = {};

    for (final entry in state.entries) {
      final item = entry.value;
      final liveProductMap = latestProducts.firstWhere(
        (p) => p['id'] == item.product.id,
        orElse: () => <String, dynamic>{},
      );

      if (liveProductMap.isEmpty) {
        resolvedMap[item.cartKey] = item;
        continue;
      }

      if (liveProductMap['is_deleted'] == true ||
          liveProductMap['is_active'] == false) {
        hasChanges = true;
        continue;
      }

      final liveProduct = ProductModel.fromMap(liveProductMap);
      final currentLabel = item.selectedUnit?.label.trim() ?? 'كرتون';

      final matchingUnit = liveProduct.units.firstWhere(
        (u) => u.label.trim() == currentLabel,
        orElse: () => liveProduct.units.firstWhere(
          (u) => u.label.trim() == 'كرتون',
          orElse: () => ProductUnit(
            label: 'كرتون',
            qty: liveProduct.itemsPerCarton ?? 1,
            price: liveProduct.price,
          ),
        ),
      );

      if (matchingUnit.label.trim() != currentLabel) {
        hasChanges = true;
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

final cartProvider = StateNotifierProvider<CartNotifier, Map<String, CartItem>>(
  (ref) => CartNotifier(),
);

final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).values.fold(0.0, (s, i) => s + i.total);
});

final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).values.fold(0, (s, i) => s + i.quantity);
});
