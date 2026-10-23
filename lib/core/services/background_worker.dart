import 'dart:convert';
import 'package:flutter/foundation.dart';

/// مسار معالجة خلفي (Isolate) لتنفيذ مهام فك وتشفير الـ JSON والفرز لمنع تعليق الشاشة تماماً (120 FPS)
class BackgroundWorker {
  BackgroundWorker._();

  static Future<List<Map<String, dynamic>>?> decodeJsonList(String rawJson) {
    return compute(_isolateDecodeJsonList, rawJson);
  }

  static Future<String> encodeJsonList(List<Map<String, dynamic>> list) {
    return compute(_isolateEncodeJsonList, list);
  }

  static Future<List<Map<String, dynamic>>> filterAndSortCatalog({
    required List<Map<String, dynamic>> items,
    required String query,
  }) {
    return compute(_isolateFilterAndSort, {
      'items': items,
      'query': query,
    });
  }

  // ── دوال التشفير الداخلية المنفذة داخل الـ Isolate المعزول ──

  static List<Map<String, dynamic>>? _isolateDecodeJsonList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
          decoded.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _isolateEncodeJsonList(List<Map<String, dynamic>> data) {
    return jsonEncode(data);
  }

  static List<Map<String, dynamic>> _isolateFilterAndSort(
      Map<String, dynamic> args) {
    final List<Map<String, dynamic>> rawItems =
        List<Map<String, dynamic>>.from(args['items'] as List);
    final String q = (args['query'] as String? ?? '').trim().toLowerCase();

    String normalize(String t) => t
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ـ', '')
        .toLowerCase()
        .trim();

    final normQ = normalize(q);

    final filtered = normQ.isEmpty
        ? rawItems
        : rawItems.where((item) {
            final name = normalize(item['name']?.toString() ?? '');
            final barcode = item['barcode']?.toString() ?? '';
            return name.contains(normQ) || barcode.contains(normQ);
          }).toList();

    filtered.sort((a, b) {
      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 999;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? '');
    });

    return filtered;
  }
}
