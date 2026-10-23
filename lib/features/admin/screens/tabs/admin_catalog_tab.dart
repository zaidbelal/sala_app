import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import 'catalog/catalog_providers.dart';
import 'catalog/categories_tab.dart';
import 'catalog/brands_tab.dart';
import 'catalog/products_tab.dart';
import 'package:flutter/services.dart';

class AdminCatalogTab extends ConsumerStatefulWidget {
  const AdminCatalogTab({super.key});
  @override
  ConsumerState<AdminCatalogTab> createState() => _AdminCatalogTabState();
}

class _AdminCatalogTabState extends ConsumerState<AdminCatalogTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        HapticFeedback.selectionClick();
        setState(() => _currentIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static const _tabs = [
    _TabMeta(label: 'الأصناف', icon: Icons.category_rounded),
    _TabMeta(label: 'الشركات', icon: Icons.business_rounded),
    _TabMeta(label: 'المنتجات', icon: Icons.inventory_2_rounded),
  ];
  @override
  Widget build(BuildContext context) {
    final catCount = ref.watch(adminCategoriesProvider).value?.length ?? 0;
    final brandCount = ref.watch(brandsProvider).value?.length ?? 0;
    final productsState = ref.watch(adminProductsProvider);
    final prodCount = (productsState.value?.length ?? 0);
    final counts = [catCount, brandCount, prodCount];
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ── الهيدر ──
          _CatalogHeader(currentTab: _tabs[_currentIndex].label),
          const SizedBox(height: 12),

          // ── شريط التبويبات ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AnimatedTabBar(
              controller: _tabController,
              tabs: _tabs,
              counts: counts,
              currentIndex: _currentIndex,
            ),
          ),
          const SizedBox(height: 12),

          // ── المحتوى ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: const [
                CategoriesTab(),
                BrandsTab(),
                ProductsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// الهيدر
// ══════════════════════════════════════════════
class _CatalogHeader extends StatelessWidget {
  final String currentTab;
  const _CatalogHeader({required this.currentTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.82),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.inventory_2_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إدارة الكتالوج',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                currentTab,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// شريط التبويبات المتحرك
// ══════════════════════════════════════════════
class _AnimatedTabBar extends StatelessWidget {
  final TabController controller;
  final List<_TabMeta> tabs;
  final List<int> counts;
  final int currentIndex;

  const _AnimatedTabBar({
    required this.controller,
    required this.tabs,
    required this.counts,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F7),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelPadding: EdgeInsets.zero,
        tabs: List.generate(tabs.length, (i) {
          final isSelected = currentIndex == i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    tabs[i].icon,
                    key: ValueKey(isSelected),
                    size: 15,
                    color: isSelected ? Colors.white : Colors.grey[500],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  tabs[i].label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : Colors.grey[500],
                  ),
                ),
                if (counts[i] > 0) ...[
                  const SizedBox(width: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${counts[i]}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// بيانات التبويب
// ══════════════════════════════════════════════
class _TabMeta {
  final String label;
  final IconData icon;
  const _TabMeta({required this.label, required this.icon});
}
