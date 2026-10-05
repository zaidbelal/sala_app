import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'package:sala/core/constants/app_adaptive_colors.dart';
import 'dart:async';

class MerchantSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClearAndExit;
  final VoidCallback onScanBarcode; // 👈 زر مسح الباركود بجانب البحث

  const MerchantSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClearAndExit,
    required this.onScanBarcode,
  });

  @override
  State<MerchantSearchBar> createState() => _MerchantSearchBarState();
}

class _MerchantSearchBarState extends State<MerchantSearchBar> {
  bool _hasText = false;
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
    return Row(
      children: [
        // ── خانة البحث ──
        Expanded(
          child: Container(
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
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 200), () {
                  if (mounted) widget.onChanged(value);
                });
              },
              textDirection: TextDirection.rtl,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'ابحث عن صنف، شركة، أو منتج...',
                hintStyle:
                    AppTextStyles.bodyMedium.copyWith(color: context.textHint),
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
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.grey, size: 20),
                        )
                      : null,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),

        const SizedBox(width: 10),

        // ── زر الباركود الاحترافي بجانب شريط البحث مباشرة ──
        GestureDetector(
          onTap: widget.onScanBarcode,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: AppRadius.lgAll,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}
