import 'package:flutter_test/flutter_test.dart';
import 'package:sala/core/utils/inventory_math.dart';

void main() {
  group('InventoryMath.cartonsFor', () {
    test('converts item quantities into cartons', () {
      expect(
        InventoryMath.cartonsFor(qty: 3, unitQty: 4, cartonCapacity: 12),
        1,
      );
    });

    test('rounds fractional cartons to four decimal places', () {
      expect(
        InventoryMath.cartonsFor(qty: 1, unitQty: 1, cartonCapacity: 3),
        0.3333,
      );
    });

    test('uses a capacity of one when the supplied capacity is invalid', () {
      expect(
        InventoryMath.cartonsFor(qty: 2, unitQty: 3, cartonCapacity: 0),
        6,
      );
    });
  });
}
