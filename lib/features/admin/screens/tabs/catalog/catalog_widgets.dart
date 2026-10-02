import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class CatalogItemTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onDelete;

  const CatalogItemTile({
    super.key,
    required this.name,
    this.subtitle,
    this.imageUrl,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(imageUrl!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const CatalogIconBox())
              : const CatalogIconBox(),
        ),
        title: Text(name,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 12, color: Colors.grey[500]))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class CatalogIconBox extends StatelessWidget {
  const CatalogIconBox({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child:
          const Icon(Icons.image_outlined, color: AppColors.primary, size: 22),
    );
  }
}

class CatalogPlaceholderImage extends StatelessWidget {
  const CatalogPlaceholderImage({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      color: const Color(0xFFF5F5F5),
      child:
          const Icon(Icons.image_outlined, color: Color(0xFFCCCCCC), size: 28),
    );
  }
}

class CatalogBadge extends StatelessWidget {
  final String label;
  final Color color;
  const CatalogBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class CatalogAddBtn extends StatelessWidget {
  final bool loading;
  const CatalogAddBtn({super.key, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.add_rounded, color: Colors.white, size: 24),
    );
  }
}

class CatalogSmallField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final TextInputType? type;
  const CatalogSmallField(
      {super.key, required this.ctrl, required this.hint, this.type});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 12, color: Color(0xFFAAAAAA)),
        filled: true,
        fillColor: const Color(0xFFF8FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
    );
  }
}

class CatalogEditField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData? icon;
  final TextInputType? type;
  const CatalogEditField(
      {super.key,
      required this.ctrl,
      required this.hint,
      this.icon,
      this.type});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 12, color: Color(0xFFAAAAAA)),
        prefixIcon:
            icon != null ? Icon(icon, size: 18, color: Colors.grey[400]) : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
    );
  }
}

class CatalogEmptyState extends StatelessWidget {
  final String label;
  final IconData icon;
  const CatalogEmptyState({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 60, color: Colors.grey[200]),
        const SizedBox(height: 10),
        Text(label,
            style: TextStyle(
                fontFamily: 'Cairo', color: Colors.grey[400], fontSize: 14)),
      ]),
    );
  }
}

class CatalogActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  const CatalogActionBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.only(
          bottomRight: isFirst ? const Radius.circular(16) : Radius.zero,
          bottomLeft: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
