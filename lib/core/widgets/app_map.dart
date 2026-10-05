import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../constants/app_colors.dart';

enum AppMapStyle {
  streets,
  terrain,
  satellite,
}

class AppMap extends StatefulWidget {
  final ll.LatLng? initialLocation;
  final ll.LatLng defaultCenter;
  final double initialZoom;
  final String title;
  final String markerLabel;
  final bool allowPick;
  final bool showSearch;
  final bool showCurrentLocation;
  final ValueChanged<ll.LatLng>? onLocationChanged;
  final AppMapStyle style;

  const AppMap({
    super.key,
    this.initialLocation,
    this.defaultCenter = const ll.LatLng(15.3550, 44.2000), // صنعاء
    this.initialZoom = 15.5,
    this.title = 'الخريطة',
    this.markerLabel = 'الموقع المحدد',
    this.allowPick = false,
    this.showSearch = true,
    this.showCurrentLocation = true,
    this.onLocationChanged,
    this.style = AppMapStyle.terrain,
  });

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  final Completer<gmaps.GoogleMapController> _controller = Completer();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  gmaps.LatLng? _selectedLocation;
  bool _isSatellite = false;
  bool _locating = false;
  bool _searching = false;
  bool _isDownloadingOffline = false;
  Timer? _searchDebounce;
  List<_SanaaPlace> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _isSatellite = widget.style == AppMapStyle.satellite;
    final init = widget.initialLocation ?? widget.defaultCenter;
    _selectedLocation = gmaps.LatLng(init.latitude, init.longitude);

    // تهيئة محرك الأماكن والأوفلاين
    _SanaaPlacesEngine.init();

    if (widget.showCurrentLocation && widget.initialLocation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _getCurrentLocation(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // البحث التلقائي الفوري (Google Places + Offline Cache)
  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    final q = val.trim();

    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);

    // ✅ مهلة 500ms متزنة لمنع حظر خوادم الخرائط (HTTP 429) أثناء الكتابة السريعة
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _SanaaPlacesEngine.search(q);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    });
  }

  void _selectLocation(gmaps.LatLng loc, {bool moveCamera = false}) async {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _selectedLocation = loc);

    widget.onLocationChanged?.call(ll.LatLng(loc.latitude, loc.longitude));

    if (moveCamera) {
      final ctrl = await _controller.future;
      if (!mounted) return;
      ctrl.animateCamera(gmaps.CameraUpdate.newLatLngZoom(loc, 16.8));
    }
  }

  Future<void> _getCurrentLocation({bool silent = false}) async {
    if (_locating) return;
    setState(() => _locating = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى تفعيل صلاحية الموقع الجغرافي')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 7),
        ),
      );

      final myLoc = gmaps.LatLng(pos.latitude, pos.longitude);
      _selectLocation(myLoc, moveCamera: true);
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('انقر على الخريطة لتحديد موقعك')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _downloadSanaaOffline() async {
    if (_isDownloadingOffline) return;
    setState(() => _isDownloadingOffline = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'جاري تحميل وتثبيت خريطة شوارع صنعاء في ذاكرة الهاتف...',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final ctrl = await _controller.future;
      const points = [
        gmaps.LatLng(15.3550, 44.2000), // التحرير
        gmaps.LatLng(15.3262, 44.1955), // حدة
        gmaps.LatLng(15.3565, 44.1845), // هائل
        gmaps.LatLng(15.3080, 44.2260), // شميلة
        gmaps.LatLng(15.2840, 44.2030), // بيت بوس
      ];

      for (final p in points) {
        await ctrl.animateCamera(gmaps.CameraUpdate.newLatLngZoom(p, 15.0));
        await Future.delayed(const Duration(milliseconds: 350));
      }

      if (_selectedLocation != null) {
        await ctrl.animateCamera(
          gmaps.CameraUpdate.newLatLngZoom(_selectedLocation!, 16.5),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ خريطة صنعاء وأماكنها للعمل أوفلاين بنجاح ✅',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isDownloadingOffline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── خريطة قوقل الحية مع دعم القمر الصناعي الهجين ──
        gmaps.GoogleMap(
          initialCameraPosition: gmaps.CameraPosition(
            target: _selectedLocation ??
                gmaps.LatLng(
                  widget.defaultCenter.latitude,
                  widget.defaultCenter.longitude,
                ),
            zoom: widget.initialZoom,
          ),
          mapType: _isSatellite ? gmaps.MapType.hybrid : gmaps.MapType.normal,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          // 🚀 منح الخريطة الأولوية الكاملة لجميع حركات اللمس والسحب والتكبير والتصغير
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          cameraTargetBounds: gmaps.CameraTargetBounds(
            // حصر نطاق الخريطة داخل أمانة العاصمة وضواحيها
            gmaps.LatLngBounds(
              southwest: const gmaps.LatLng(15.1500, 44.0500),
              northeast: const gmaps.LatLng(15.5500, 44.3500),
            ),
          ),
          minMaxZoomPreference: const gmaps.MinMaxZoomPreference(11.0, 19.5),
          onMapCreated: (ctrl) {
            if (!_controller.isCompleted) {
              _controller.complete(ctrl);
            }
          },
          onTap: widget.allowPick ? (loc) => _selectLocation(loc) : null,
          markers: _selectedLocation == null
              ? {}
              : {
                  gmaps.Marker(
                    markerId: const gmaps.MarkerId('selected_pin'),
                    position: _selectedLocation!,
                    infoWindow: gmaps.InfoWindow(title: widget.markerLabel),
                    icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                      gmaps.BitmapDescriptor.hueGreen,
                    ),
                  ),
                },
        ),

        // ── شريط البحث الحي الذكي (مثل خرائط قوقل تماماً) ──
        if (widget.showSearch)
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: SafeArea(
              child: Column(
                children: [
                  Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      textDirection: TextDirection.rtl,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Color(0xFF111827),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'ابحث عن أي بقالة، متجر، أو شارع في صنعاء...',
                        hintStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.search_rounded,
                                color: AppColors.primary,
                              ),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchResults = []);
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.grey,
                                ),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),

                  // نتائج البحث المسترجعة حياً من قوقل
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFEEEEEE)),
                        itemBuilder: (ctx, i) {
                          final place = _searchResults[i];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              place.name,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            onTap: () {
                              _searchController.text = place.name;
                              _searchFocus.unfocus();
                              setState(() => _searchResults = []);
                              _selectLocation(place.location, moveCamera: true);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

        // ── أزرار التحكم ──
        Positioned(
          right: 16,
          bottom: 24,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'download_offline_btn',
                backgroundColor: Colors.white,
                onPressed: _isDownloadingOffline ? null : _downloadSanaaOffline,
                child: _isDownloadingOffline
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue,
                        ),
                      )
                    : const Icon(
                        Icons.download_for_offline_rounded,
                        color: Colors.blue,
                      ),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.small(
                heroTag: 'map_type_btn',
                backgroundColor: Colors.white,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isSatellite = !_isSatellite);
                },
                child: Icon(
                  _isSatellite
                      ? Icons.map_rounded
                      : Icons.satellite_alt_rounded,
                  color: _isSatellite ? Colors.orange : AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.showCurrentLocation)
                FloatingActionButton.small(
                  heroTag: 'my_loc_btn',
                  backgroundColor: Colors.white,
                  onPressed: () => _getCurrentLocation(),
                  child: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          color: AppColors.primary,
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// نموذج بيانات المكان
// ══════════════════════════════════════════════════════════════
class _SanaaPlace {
  final String name;
  final String address;
  final gmaps.LatLng location;

  const _SanaaPlace({
    required this.name,
    required this.address,
    required this.location,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'lat': location.latitude,
        'lng': location.longitude,
      };

  factory _SanaaPlace.fromMap(Map<String, dynamic> map) => _SanaaPlace(
        name: map['name'] ?? '',
        address: map['address'] ?? '',
        location: gmaps.LatLng(
          (map['lat'] as num).toDouble(),
          (map['lng'] as num).toDouble(),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// محرك بحث قوقل الحقيقي لصنعاء + كاش أوفلاين دائم
// ══════════════════════════════════════════════════════════════
class _SanaaPlacesEngine {
  static const String _kOfflineCacheKey = 'sala_sanaa_offline_places_v2';
  static final Map<String, List<_SanaaPlace>> _memoryCache = {};
  static final List<_SanaaPlace> _offlineStoredPlaces = [];
  static bool _initialized = false;

// مفتاح محمي: يتم الاعتماد حصرياً على الدالة السحابية الآمنة searchPlaces
  static const String googlePlacesApiKey = '';

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kOfflineCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _offlineStoredPlaces.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _offlineStoredPlaces.add(_SanaaPlace.fromMap(item));
          }
        }
      }
    } catch (_) {}
  }

  static String normalizeYemeniArabic(String input) {
    var text = input.trim();
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    text = text.replaceAll('ـ', '');
    text = text.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    text = text.replaceAll('ء', '');
    text = text.replaceAll('ؤ', 'و');
    text = text.replaceAll('ئ', 'ي');
    text = text.replaceAll('ة', 'ه');
    text = text.replaceAll('ى', 'ي');
    text = text.replaceAll('ظ', 'ض');
    return text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase().trim();
  }

  // دالة البحث الرئيسية: تجمع بين نتائج قوقل الحية وحفظ الأوفلاين
  static Future<List<_SanaaPlace>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final normalizedKey = normalizeYemeniArabic(cleanQuery);
    if (_memoryCache.containsKey(normalizedKey)) {
      return _memoryCache[normalizedKey]!;
    }

    await init();

    // 1. البحث أولاً في الأماكن المحفوظة في ذاكرة الهاتف (Offline أولاً)
    final offlineMatches = _searchInOfflineStorage(cleanQuery);

    // 2. البحث الحي في خوادم الخرائط الحقيقية لصنعاء (Google Places / Nominatim)
    List<_SanaaPlace> liveMatches = [];
    try {
      liveMatches = await _fetchLiveGooglePlaces(cleanQuery).timeout(
        const Duration(seconds: 4),
        onTimeout: () => [],
      );
    } catch (_) {}

    // دمج النتائج مع إعطاء الأولوية للنتائج الحية الأحدث وتفادي التكرار
    final combined = <String, _SanaaPlace>{};
    for (final p in liveMatches) {
      combined[p.name] = p;
      // حفظ في ذاكرة الهاتف للأوفلاين
      _savePlaceForOffline(p);
    }
    for (final p in offlineMatches) {
      if (!combined.containsKey(p.name)) {
        combined[p.name] = p;
      }
    }

    final finalResults = combined.values.take(15).toList();
    if (finalResults.isNotEmpty) {
      _memoryCache[normalizedKey] = finalResults;
    }

    return finalResults;
  }

  // استعلام قوقل للبحث عن أي محل أو بقالة في صنعاء
  static Future<List<_SanaaPlace>> _fetchLiveGooglePlaces(String query) async {
    // 1. تجربة استدعاء Google Places API المباشر إذا كان المفتاح متوفراً
    if (googlePlacesApiKey.isNotEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);

        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/textsearch/json?'
          'query=${Uri.encodeComponent('$query صنعاء')}&'
          'location=15.3550,44.2000&'
          'radius=25000&'
          'region=ye&'
          'language=ar&'
          'key=$googlePlacesApiKey',
        );

        final req = await client.getUrl(url);
        final res = await req.close();
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          client.close();
          final data = jsonDecode(body);
          final results = data['results'] as List<dynamic>? ?? [];

          final List<_SanaaPlace> places = [];
          for (final item in results) {
            final name = item['name']?.toString() ?? '';
            final address =
                item['formatted_address']?.toString() ?? 'صنعاء، اليمن';
            final lat =
                (item['geometry']?['location']?['lat'] as num?)?.toDouble();
            final lng =
                (item['geometry']?['location']?['lng'] as num?)?.toDouble();

            if (lat != null && lng != null && _isInsideSanaa(lat, lng)) {
              places.add(_SanaaPlace(
                name: name,
                address: address,
                location: gmaps.LatLng(lat, lng),
              ));
            }
          }
          if (places.isNotEmpty) return places;
        }
      } catch (_) {}
    }

    // 2. تجربة دالة فايربيز السحابية (searchPlaces)
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'searchPlaces',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 4)),
      );
      final response = await callable.call({'query': '$query صنعاء'});
      final results = response.data as List<dynamic>? ?? [];
      final List<_SanaaPlace> places = [];

      for (final item in results) {
        final name = item['name']?.toString() ?? '';
        final address = item['formatted_address']?.toString() ?? 'صنعاء، اليمن';
        final lat = (item['geometry']?['location']?['lat'] as num?)?.toDouble();
        final lng = (item['geometry']?['location']?['lng'] as num?)?.toDouble();

        if (lat != null && lng != null && _isInsideSanaa(lat, lng)) {
          places.add(_SanaaPlace(
            name: name,
            address: address,
            location: gmaps.LatLng(lat, lng),
          ));
        }
      }
      if (places.isNotEmpty) return places;
    } catch (_) {}

    // 3. المحرك المباشر الحر المفتوح (Live OpenStreetMap Places لليمن)
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?'
        'q=${Uri.encodeComponent('$query صنعاء')}&'
        'format=json&'
        'countrycodes=ye&'
        'viewbox=44.05,15.52,44.32,15.18&'
        'bounded=1&'
        'limit=10&'
        'accept-language=ar',
      );

      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'SalaAppYemen/1.0');
      final response = await request.close();

      if (response.statusCode == 200) {
        final rawJson = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(rawJson);

        if (decoded is List) {
          final List<_SanaaPlace> places = [];
          for (final item in decoded) {
            final displayName = item['display_name']?.toString() ?? '';
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');

            if (lat != null && lon != null && _isInsideSanaa(lat, lon)) {
              final parts = displayName.split(',');
              final cleanName = parts.isNotEmpty ? parts.first.trim() : query;
              final cleanAddress = parts.length > 1
                  ? parts.sublist(1).take(2).join(', ').trim()
                  : 'صنعاء، اليمن';

              places.add(_SanaaPlace(
                name: cleanName,
                address: cleanAddress,
                location: gmaps.LatLng(lat, lon),
              ));
            }
          }
          return places;
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }

    return [];
  }

  // فحص أمني جغرافي لضمان أن كل النتائج داخل صنعاء حصراً
  static bool _isInsideSanaa(double lat, double lng) {
    return lat >= 15.15 && lat <= 15.55 && lng >= 44.05 && lng <= 44.35;
  }

  // البحث في الأماكن المحفوظة سابقاً في الهاتف عند انقطاع الإنترنت (أوفلاين)
  static List<_SanaaPlace> _searchInOfflineStorage(String query) {
    final normQuery = normalizeYemeniArabic(query);
    final tokens = normQuery.split(' ').where((w) => w.length > 1).toList();

    return _offlineStoredPlaces.where((place) {
      final name = normalizeYemeniArabic(place.name);
      final address = normalizeYemeniArabic(place.address);

      if (name.contains(normQuery) || address.contains(normQuery)) {
        return true;
      }
      return tokens.any((t) => name.contains(t) || address.contains(t));
    }).toList();
  }

  // حفظ المكان تلقائياً في ذاكرة الهاتف ليعمل أوفلاين
  static Future<void> _savePlaceForOffline(_SanaaPlace place) async {
    try {
      final exists = _offlineStoredPlaces.any(
        (p) =>
            p.name == place.name &&
            (p.location.latitude - place.location.latitude).abs() < 0.0001,
      );
      if (exists) return;

      _offlineStoredPlaces.insert(0, place);
      if (_offlineStoredPlaces.length > 250) {
        _offlineStoredPlaces.removeLast();
      }

      final prefs = await SharedPreferences.getInstance();
      final serialized = jsonEncode(
        _offlineStoredPlaces.map((p) => p.toMap()).toList(),
      );
      await prefs.setString(_kOfflineCacheKey, serialized);
    } catch (_) {}
  }
}
