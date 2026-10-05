import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_adaptive_colors.dart';

class PhoneInputField extends StatefulWidget {
  final TextEditingController controller;
  final void Function(bool isValid) onChanged;

  const PhoneInputField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField>
    with SingleTickerProviderStateMixin {
  late AnimationController _colorAnimController;
  late Animation<Color?> _borderColorAnim;

  String _errorMessage = '';
  int _digitCount = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();

    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _borderColorAnim = ColorTween(
      begin: AppColors.grey300,
      end: AppColors.primary,
    ).animate(CurvedAnimation(
      parent: _colorAnimController,
      curve: Curves.easeInOut,
    ));

    final text = widget.controller.text;
    _digitCount = text.length;
    _isComplete = _digitCount == 9 && (text.isEmpty || text[0] == '7');
    if (_isComplete) {
      _colorAnimController.value = 1.0;
    }

    widget.controller.addListener(_onTextChanged);

    if (text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onChanged(_isComplete && _errorMessage.isEmpty);
        }
      });
    }
  }

  void _onTextChanged() {
    var text = widget.controller.text;

    // 🚀 تنظيف تلقائي للرقم في حال قام المستخدم بلصق رقم يبدأ بصفر محلي (مثل 077...)
    if (text.startsWith('0') && text.length > 1) {
      text = text.substring(1);
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      return;
    }

    final count = text.length;

    setState(() {
      _digitCount = count;
      _errorMessage = '';

      if (count > 0 && text[0] != '7') {
        _errorMessage = 'يجب أن يبدأ الرقم بـ 7';
        _isComplete = false;
        _colorAnimController.reverse();
      } else if (count == 9) {
        _isComplete = true;
        _colorAnimController.forward();
      } else {
        _isComplete = false;
        _colorAnimController.reverse();
      }
    });

    if (mounted) {
      widget.onChanged(_isComplete && _errorMessage.isEmpty);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _colorAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── الخانة الرئيسية ──
        AnimatedBuilder(
          animation: _borderColorAnim,
          builder: (context, _) {
            final borderColor = _errorMessage.isNotEmpty
                ? AppColors.error
                : (_borderColorAnim.value ?? AppColors.grey300);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: AppRadius.lgAll,
                border: Border.all(
                  color: borderColor,
                  width: _isComplete ? 2.0 : 1.5,
                ),
                boxShadow: _isComplete
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  // ── علم اليمن + المفتاح ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: _errorMessage.isNotEmpty
                              ? AppColors.error.withValues(alpha: 0.3)
                              : context.borderColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // العلم
                        const Text('🇾🇪', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        // المفتاح
                        Text(
                          '+967',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: context.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── حقل الإدخال ──
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      maxLength: 9,
                      style: AppTextStyles.titleLarge.copyWith(
                        letterSpacing: 2.5,
                        color: context.textPrimary,
                      ),
                      inputFormatters: [
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          const arabicDigits = {
                            '٠': '0',
                            '١': '1',
                            '٢': '2',
                            '٣': '3',
                            '٤': '4',
                            '٥': '5',
                            '٦': '6',
                            '٧': '7',
                            '٨': '8',
                            '٩': '9',
                          };
                          var text = newValue.text;
                          arabicDigits.forEach((ar, en) {
                            text = text.replaceAll(ar, en);
                          });
                          text = text.replaceAll(RegExp(r'[^0-9]'), '');

                          var newOffset = newValue.selection.baseOffset;
                          if (text.startsWith('0')) {
                            text = text.substring(1);
                            newOffset = (newOffset - 1).clamp(0, text.length);
                          }
                          if (text.length > 9) {
                            text = text.substring(0, 9);
                            newOffset = newOffset.clamp(0, 9);
                          }
                          return TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: newOffset.clamp(0, text.length),
                            ),
                          );
                        }),
                      ],
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '7XXXXXXXX',
                        hintStyle: AppTextStyles.hint.copyWith(
                          letterSpacing: 1.5,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),

                  // ── العداد ──
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Text(
                        '$_digitCount/9',
                        key: ValueKey(_digitCount),
                        style: AppTextStyles.labelMedium.copyWith(
                          color: _isComplete
                              ? AppColors.primary
                              : AppColors.grey500,
                          fontWeight:
                              _isComplete ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),
                ],
              ),
            );
          },
        ),

        // ── رسالة الخطأ ──
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _errorMessage.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, right: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.error,
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _errorMessage,
                        style: AppTextStyles.error,
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── مؤشر التقدم ──
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: AppRadius.circleAll,
          child: LinearProgressIndicator(
            value: _digitCount / 9,
            minHeight: 3,
            backgroundColor: context.bgInput,
            valueColor: AlwaysStoppedAnimation<Color>(
              _isComplete ? AppColors.primary : AppColors.secondary,
            ),
          ),
        ),
      ],
    );
  }
}
