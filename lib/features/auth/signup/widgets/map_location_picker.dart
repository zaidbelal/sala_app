// ==================================================
// FILE: lib/features/auth/signup/widgets/map_location_picker.dart
// ==================================================

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_map.dart';

const _districtCenter = LatLng(15.3550, 44.2000);

class MapLocationPickerSheet extends StatefulWidget {
  final LatLng? initialLocation;

  const MapLocationPickerSheet({
    super.key,
    this.initialLocation,
  });

  @override
  State<MapLocationPickerSheet> createState() => _MapLocationPickerSheetState();
}

class _MapLocationPickerSheetState extends State<MapLocationPickerSheet> {
  LatLng? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation ?? _districtCenter;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.93,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'حدد موقع البقالة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppMap(
                initialLocation: widget.initialLocation,
                defaultCenter: _districtCenter,
                initialZoom: widget.initialLocation != null ? 17.0 : 16.0,
                title: 'موقع البقالة',
                markerLabel: 'موقع البقالة',
                allowPick: true,
                showSearch: true,
                showCurrentLocation: true,
                onLocationChanged: (location) {
                  setState(() => _selectedLocation = location);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _selectedLocation == null
                      ? null
                      : () => Navigator.pop(context, _selectedLocation),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(
                    _selectedLocation == null
                        ? 'حدد الموقع أولاً'
                        : 'تأكيد موقع البقالة',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
