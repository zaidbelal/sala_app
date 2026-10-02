import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'dart:async';

class MerchantSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClearAndExit; // X بدون نص → رجوع للرئيسية

  const MerchantSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClearAndExit,
  });

  @override
  State<MerchantSearchBar> createState() => _MerchantSearchBarState();
}

class _MerchantSearchBarState extends State<MerchantSearchBar> {
  bool _hasText = false;
  // 🚀 Debounce: لا يُطلق البحث إلا بعد 400ms من توقف الكتابة
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onXPressed() {
    if (_hasText) {
      _debounce?.cancel();
      widget.controller.clear();
      widget.onChanged('');
    } else {
      widget.onClearAndExit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        onChanged: (value) {
          // 🚀 استجابة سريعة جداً (200 ملي ثانية فقط بدلاً من 1000)
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 200), () {
            if (mounted) {
              widget.onChanged(value);
            }
          });
        },
        textDirection: TextDirection.rtl,
        style: AppTextStyles.bodyMedium.copyWith(color: context.textPrimary),
        decoration: InputDecoration(
          hintText: 'ابحث عن صنف، شركة، أو منتج...',
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: context.textHint,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.primary,
            size: 22,
          ),
          suffixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _hasText
                ? IconButton(
                    key: const ValueKey('x_text'),
                    onPressed: _onXPressed,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.grey,
                      size: 20,
                    ),
                  )
                : IconButton(
                    key: const ValueKey('x_empty'),
                    onPressed: _onXPressed,
                    icon: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.grey[400],
                      size: 18,
                    ),
                  ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
