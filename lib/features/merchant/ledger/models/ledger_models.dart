import 'package:cloud_firestore/cloud_firestore.dart';

/// نموذج بيانات الزبون في دفتر الديون
class LedgerCustomer {
  final String id;
  final String merchantId;
  final String name;
  final String phone;
  final double currentBalance; // إجمالي الدين المتبقي عليه
  final double creditLimit; // سقف الدين الأقصى المسموح له
  final int? salaryDay; // يوم الراتب الشهري للتذكير (مثال: يوم 28)
  final DateTime? lastReminderSentAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LedgerCustomer({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.phone,
    required this.currentBalance,
    this.creditLimit = 0.0,
    this.salaryDay,
    this.lastReminderSentAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// تحويل المبالغ المالية إلى أعداد صحيحة بالقروش/الفلوس (Integer Cents) لمنع هلوسة الفواصل التراكمية نهائياً
  static int toCents(num val) => (val * 100).round();
  static double fromCents(int cents) => cents / 100.0;
  static double sanitizeAmount(num val) => fromCents(toCents(val));

  int get balanceCents => toCents(currentBalance);
  int get creditLimitCents => toCents(creditLimit);

  bool get isOverLimit =>
      creditLimitCents > 0 && balanceCents > creditLimitCents;
  double get limitProgress => creditLimitCents > 0
      ? (balanceCents / creditLimitCents).clamp(0.0, 1.0)
      : 0.0;
  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'name': name,
        'phone': phone,
        'current_balance': currentBalance,
        'credit_limit': creditLimit,
        if (salaryDay != null) 'salary_day': salaryDay,
        if (lastReminderSentAt != null)
          'last_reminder_sent_at': Timestamp.fromDate(lastReminderSentAt!),
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(updatedAt),
      };

  factory LedgerCustomer.fromMap(Map<String, dynamic> m) {
    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return LedgerCustomer(
      id: m['id']?.toString() ?? '',
      merchantId: m['merchant_id']?.toString() ?? '',
      name: m['name']?.toString() ?? 'زبون',
      phone: m['phone']?.toString() ?? '',
      currentBalance:
          sanitizeAmount((m['current_balance'] as num?)?.toDouble() ?? 0.0),
      creditLimit:
          sanitizeAmount((m['credit_limit'] as num?)?.toDouble() ?? 0.0),
      salaryDay: (m['salary_day'] as num?)?.toInt(),
      lastReminderSentAt: m['last_reminder_sent_at'] != null
          ? parseDate(m['last_reminder_sent_at'])
          : null,
      createdAt: parseDate(m['created_at']),
      updatedAt: parseDate(m['updated_at']),
    );
  }
}

/// حركة مالية في حساب الزبون (دين جديد أو سداد دفعة نقدية)
class LedgerEntry {
  final String id;
  final String merchantId;
  final String customerId;
  final String type; // 'debt' (أخذ دين +) أو 'payment' (سدد نقد -)
  final double amount;
  final String? notes;
  final List<Map<String, dynamic>> items; // الأصناف بالباركود إن وجدت
  final bool isVoided; // ملغي / مشطوب
  final DateTime createdAt;

  const LedgerEntry({
    required this.id,
    required this.merchantId,
    required this.customerId,
    required this.type,
    required this.amount,
    this.notes,
    this.items = const [],
    this.isVoided = false,
    required this.createdAt,
  });

  bool get isDebt => type == 'debt';

  Map<String, dynamic> toMap() => {
        'id': id,
        'merchant_id': merchantId,
        'customer_id': customerId,
        'type': type,
        'amount': amount,
        'is_voided': isVoided,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'items': items,
        'created_at': Timestamp.fromDate(createdAt),
      };

  factory LedgerEntry.fromMap(Map<String, dynamic> m) {
    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return LedgerEntry(
      id: m['id']?.toString() ?? '',
      merchantId: m['merchant_id']?.toString() ?? '',
      customerId: m['customer_id']?.toString() ?? '',
      type: m['type']?.toString() ?? 'debt',
      amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
      notes: m['notes']?.toString(),
      items: (m['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      isVoided: m['is_voided'] == true,
      createdAt: parseDate(m['created_at']),
    );
  }
}
