import 'package:flutter/material.dart';
import '../services/products_service.dart';
import '../widgets/product_details_sheet.dart';

class ProductDetailScreen extends StatelessWidget {
  final ProductModel product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ProductDetailsSheet(product: product),
      ),
    );
  }
}
