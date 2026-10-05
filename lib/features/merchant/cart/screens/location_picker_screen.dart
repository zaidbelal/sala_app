import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/widgets/app_map.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // 🚀 يبدأ بموقع صنعاء مباشرة حتى يكون الزر مفعلاً وجاهزاً للضغط دائماً
  LatLng _selectedLocation = const LatLng(15.3694, 44.1910);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تحديد موقع التوصيل',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: AppMap(
        initialLocation:
            null, // 🚀 يسمح بالانتقال التلقائي الفوري لموقع التاجر بالـ GPS
        defaultCenter: _selectedLocation,
        initialZoom: 17.0,
        title: 'موقع التوصيل',
        markerLabel: 'موقعي الحالي',
        allowPick: true,
        showSearch: true,
        showCurrentLocation: true,
        style: AppMapStyle.terrain,
        onLocationChanged: (location) {
          setState(() => _selectedLocation = location);
        },
      ),
      // 🚀 تم وضع الزر في شريط سفلي مستقل لمنع التداخل مع أزرار الخريطة وجعله قابلاً للضغط دائماً
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop(_selectedLocation);
            },
            icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
            label: const Text(
              'تأكيد موقع التوصيل',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
