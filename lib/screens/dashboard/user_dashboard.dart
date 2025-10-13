import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
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
  String _status = "Fetching device location...";
  bool _isLoading = false;
  bool _isCalibrating = false;
  StreamSubscription<Position>? _positionStream;

  // 📍 Set your OJT Site location here
  static const LatLng ojtSite = LatLng(10.593059988638895, 122.60107014352693);
  static const double allowedRadius = 30; // meters

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _logout(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ChoiceScreen()),
    );
  }

  /// 🚀 Start location tracking with best accuracy
  Future<void> _startLocationUpdates() async {
    setState(() => _isLoading = true);
    await _positionStream?.cancel();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = "❌ Location services are disabled.";
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
            "⚠️ Location permissions are permanently denied. Enable them in settings.";
        _isLoading = false;
      });
      return;
    }

    Position initialPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    final initialLoc = LatLng(initialPosition.latitude, initialPosition.longitude);
    final initialDistance =
        const Distance().as(LengthUnit.Meter, initialLoc, ojtSite);

    setState(() {
      _currentLocation = initialLoc;
      _isInsideArea = initialDistance <= allowedRadius;
      _status = _isInsideArea
          ? "✅ Inside OJT area (${initialDistance.toStringAsFixed(1)}m)."
          : "❌ Outside OJT area (${initialDistance.toStringAsFixed(1)}m).";
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      if (!mounted) return;
      final newLoc = LatLng(position.latitude, position.longitude);
      final distance = const Distance().as(LengthUnit.Meter, newLoc, ojtSite);

      // Ignore big GPS jumps
      if (_currentLocation != null) {
        final jump = const Distance()
            .as(LengthUnit.Meter, _currentLocation!, newLoc);
        if (jump > 100) return;
      }

      setState(() {
        _currentLocation = newLoc;
        _isInsideArea = distance <= allowedRadius;
        _status = _isInsideArea
            ? "✅ Inside OJT site (${distance.toStringAsFixed(1)}m)."
            : "❌ Outside OJT site (${distance.toStringAsFixed(1)}m).";
        _isLoading = false;
      });
    });
  }

  /// ✅ Mark attendance
  void _markAttendance() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isInsideArea
              ? "✅ Attendance marked successfully!"
              : "❌ You are outside the OJT site area.",
        ),
        backgroundColor: _isInsideArea ? Colors.green : Colors.red,
      ),
    );
  }

  /// 🎯 Calibrate GPS manually (force accuracy refresh)
  Future<void> _calibrateGPS() async {
    setState(() => _isCalibrating = true);
    try {
      // Request a high accuracy location (forces recalibration)
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      // Open Google Location Accuracy settings
      await AppSettings.openAppSettings(
          type: AppSettingsType.location); // 🔧 Opens Location Settings

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🧭 GPS calibration triggered. Move your phone in a figure-8 motion."),
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

  Future<void> _onRefresh() async {
    await _startLocationUpdates();
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter = _currentLocation ?? ojtSite;

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
                // 👤 Header
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

                // ⚡ Quick Actions
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
                      label: "Refresh GPS",
                      onTap: _startLocationUpdates,
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

                // 📍 GPS Status
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 14,
                    color: _isInsideArea ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 12),

                // 🗺️ Map Display
                SizedBox(
                  height: 400,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: mapCenter,
                        initialZoom: 17,
                        interactionOptions:
                            const InteractionOptions(flags: InteractiveFlag.all),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.ojtconnect',
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: ojtSite,
                              color: Colors.blue.withOpacity(0.2),
                              borderStrokeWidth: 2,
                              borderColor: Colors.blue,
                              radius: allowedRadius,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: ojtSite,
                              width: 60,
                              height: 60,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
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
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 📦 Reusable Dashboard Button
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
