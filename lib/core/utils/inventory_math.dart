/// دالة مشتركة موحّدة لحساب عدد الكراتين المقابلة لكمية مُباعة/مُرتجعة
/// من وحدة فرعية (unit)، بدلاً من تكرار هذه الصيغة في عدة ملفات.
class InventoryMath {
  InventoryMath._();

  static double cartonsFor({
    required num qty,
    required int unitQty,
    required int cartonCapacity,
  }) {
    final capacity = cartonCapacity > 0 ? cartonCapacity : 1;
    return (qty * unitQty) / capacity;
  }
}
