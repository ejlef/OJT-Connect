import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geodesy/geodesy.dart';
import 'package:app_settings/app_settings.dart';
import '../auth/choice_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  LatLng? _currentLocation;
  bool _isInsideArea = false;
  String _status = "Loading OJT Zone...";
  bool _isLoading = false;
  bool _isCalibrating = false;
  bool _zoneLoaded = false;
  StreamSubscription<Position>? _geofenceStream;

  final Geodesy geodesy = Geodesy();
  List<LatLng> ojtPolygon = [];

  @override
  void initState() {
    super.initState();
    _loadPolygonFromGeoJSON();
  }

  // 🟦 Load polygon points from assets/ojt_zone.geojson
  Future<void> _loadPolygonFromGeoJSON() async {
    try {
      final geojsonString = await rootBundle.loadString(
        'assets/ojtzone/ojt_zone.geojson',
      );
      final data = jsonDecode(geojsonString);

      final geometry = data["features"][0]["geometry"];
      final type = geometry["type"];
      List<dynamic> coords = [];

      if (type == "Polygon") {
        coords = geometry["coordinates"][0];
      } else if (type == "MultiPolygon") {
        coords = geometry["coordinates"][0][0];
      } else {
        throw Exception("Unsupported geometry type: $type");
      }

      setState(() {
        ojtPolygon = coords
            .map<LatLng>((coord) => LatLng(coord[1], coord[0])) // [lon, lat]
            .toList();
        _zoneLoaded = true;
        _status = "OJT Zone loaded ✅";
      });

      _startGeofencing();
    } catch (e) {
      setState(() {
        _status = "❌ Failed to load OJT Zone: $e";
      });
    }
  }

  @override
  void dispose() {
    _geofenceStream?.cancel();
    super.dispose();
  }

  void _logout(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ChoiceScreen()),
    );
  }

  // ✅ Start Geofence Monitoring
  Future<void> _startGeofencing() async {
    if (!_zoneLoaded) return;

    setState(() {
      _isLoading = true;
      _status = "Activating geofence...";
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = "❌ Location service disabled.";
        _isLoading = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _status = "❌ Location permission denied.";
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status =
            "⚠️ Location permissions permanently denied. Enable in settings.";
        _isLoading = false;
      });
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    _updateLocation(LatLng(position.latitude, position.longitude));

    _geofenceStream?.cancel();
    _geofenceStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 2,
          ),
        ).listen((Position pos) {
          _updateLocation(LatLng(pos.latitude, pos.longitude));
        });

    setState(() => _isLoading = false);
  }

  // 📍 Update position and detect geofence enter/exit
  void _updateLocation(LatLng newLoc) {
    if (ojtPolygon.isEmpty) return;

    bool isInside = geodesy.isGeoPointInPolygon(newLoc, ojtPolygon);

    if (_isInsideArea != isInside) {
      _isInsideArea = isInside;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isInside ? "🚪 ENTERED OJT Zone" : "🚶‍♂️ EXITED OJT Zone",
          ),
          backgroundColor: isInside ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _currentLocation = newLoc;
      _isInsideArea = isInside;
      _status = isInside ? "✅ Inside OJT Zone" : "❌ Outside OJT Zone";
    });
  }

  // 🧭 Calibrate GPS manually
  Future<void> _calibrateGPS() async {
    setState(() => _isCalibrating = true);
    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      await AppSettings.openAppSettings(type: AppSettingsType.location);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "🧭 Move your phone in a figure-8 to improve GPS accuracy.",
          ),
          backgroundColor: Colors.blueAccent,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Calibration failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() => _isCalibrating = false);
  }

  // ✅ Mark attendance
  void _markAttendance() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isInsideArea
              ? "✅ Attendance marked successfully!"
              : "❌ You are outside the OJT zone.",
        ),
        backgroundColor: _isInsideArea ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _onRefresh() async {
    await _startGeofencing();
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter =
        _currentLocation ??
        (ojtPolygon.isNotEmpty ? ojtPolygon.first : const LatLng(10.6, 122.6));

    return Scaffold(
      appBar: AppBar(
        title: const Text('OJT Connect - Student'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    CircleAvatar(
                      radius: 28,
                      child: Icon(Icons.person, size: 32),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Welcome, Student!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                const Text(
                  "Quick Actions",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _DashboardButton(
                      icon: Icons.check_circle,
                      label: "Attendance",
                      onTap: _markAttendance,
                    ),
                    _DashboardButton(
                      icon: Icons.refresh,
                      label: "Restart GPS",
                      onTap: _startGeofencing,
                      isLoading: _isLoading,
                    ),
                    _DashboardButton(
                      icon: Icons.my_location,
                      label: "Calibrate",
                      onTap: _calibrateGPS,
                      isLoading: _isCalibrating,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 14,
                    color: _isInsideArea ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 12),

                if (_zoneLoaded)
                  SizedBox(
                    height: 400,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: mapCenter,
                          initialZoom: 17,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.ojtconnect',
                          ),
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: ojtPolygon,
                                borderColor: Colors.blue,
                                borderStrokeWidth: 2,
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              if (_currentLocation != null)
                                Marker(
                                  point: _currentLocation!,
                                  width: 60,
                                  height: 60,
                                  child: const Icon(
                                    Icons.my_location,
                                    color: Colors.green,
                                    size: 35,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const _DashboardButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.blue.shade100,
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.blue,
                    ),
                  )
                : Icon(icon, size: 28, color: Colors.blue),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
