import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geodesy/geodesy.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../auth/choice_screen.dart';

class UserDashboard extends StatefulWidget {
  final String userId;
  const UserDashboard({super.key, required this.userId});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  LatLng? _currentLocation;
  bool _isInsideArea = false;
  bool _checkedIn = false;
  bool _zoneLoaded = false;
  bool _isLoading = false;
  bool _isCalibrating = false;
  String _status = "Loading OJT Zones...";
  String _fname = "";
  String _lname = "";
  String _course = "";
  String _schoolId = "";

  String? _teamId;
  String? _teamName;
  List<LatLng> teamPolygon = [];

  StreamSubscription<Position>? _geofenceStream;
  final Geodesy geodesy = Geodesy();

  @override
  void initState() {
    super.initState();
    _loadUserData().then((_) => _loadTeamPolygon());
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _fname = data['fname'] ?? '';
          _lname = data['lname'] ?? '';
          _course = data['course'] ?? '';
          _schoolId = data['schoolId'] ?? '';
          _teamId = data['teamId'];
        });
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
    }
  }

  Future<void> _loadTeamPolygon() async {
    if (_teamId == null) {
      setState(() {
        _status = "❌ You are not assigned to a team";
      });
      return;
    }

    try {
      setState(() => _status = "Fetching your team OJT Zone...");

      final teamDoc = await FirebaseFirestore.instance
          .collection('teams')
          .doc(_teamId)
          .get();

      if (!teamDoc.exists) {
        setState(() => _status = "❌ No OJT Zone found for your team");
        return;
      }

      final data = teamDoc.data()!;
      _teamName = data['name'];

      final zone = Map<String, dynamic>.from(data['zone']);
      final northEast = Map<String, dynamic>.from(zone['northEast']);
      final southWest = Map<String, dynamic>.from(zone['southWest']);

      final neLat = (northEast['lat'] as num).toDouble();
      final neLng = (northEast['lng'] as num).toDouble();
      final swLat = (southWest['lat'] as num).toDouble();
      final swLng = (southWest['lng'] as num).toDouble();

      teamPolygon = [
        LatLng(swLat, swLng),
        LatLng(swLat, neLng),
        LatLng(neLat, neLng),
        LatLng(neLat, swLng),
        LatLng(swLat, swLng),
      ];

      setState(() {
        _zoneLoaded = true;
        _status = "✅ Your team OJT Zone loaded!";
      });

      _startGeofencing();
    } catch (e) {
      setState(() => _status = "❌ Failed to load team OJT Zone: $e");
    }
  }

  @override
  void dispose() {
    _geofenceStream?.cancel();
    super.dispose();
  }

  Future<void> _startGeofencing() async {
    if (!_zoneLoaded) return;

    setState(() => _isLoading = true);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = "❌ Location service disabled";
        _isLoading = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _status = "❌ Location permission denied";
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status = "⚠️ Location permission permanently denied";
        _isLoading = false;
      });
      return;
    }

    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    _updateLocation(LatLng(pos.latitude, pos.longitude));

    _geofenceStream?.cancel();
    _geofenceStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) => _updateLocation(LatLng(pos.latitude, pos.longitude)));

    setState(() => _isLoading = false);
  }

  void _updateLocation(LatLng newLoc) {
    bool insideZone = false;
    if (teamPolygon.isNotEmpty) {
      insideZone = geodesy.isGeoPointInPolygon(newLoc, teamPolygon);
    }

    if (_isInsideArea != insideZone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            insideZone ? "🚪 ENTERED OJT Zone" : "🚶‍♂️ EXITED OJT Zone",
          ),
          backgroundColor: insideZone ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _currentLocation = newLoc;
      _isInsideArea = insideZone;
      _status = insideZone ? "✅ Inside OJT Zone" : "❌ Outside OJT Zone";
    });
  }

  Future<void> _markAttendance() async {
    if (_teamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Only team members can mark attendance"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_isInsideArea || _currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ You must be inside the OJT Zone"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String time = DateFormat('HH:mm:ss').format(DateTime.now());
      String status = _checkedIn ? "check-out" : "check-in";

      await FirebaseFirestore.instance.collection('attendance').add({
        'studentId': widget.userId,
        'studentName': '$_fname $_lname',
        'course': _course,
        'schoolId': _schoolId,
        'teamId': _teamId,
        'teamName': _teamName,
        'date': date,
        'time': time,
        'status': status,
        'insideZone': _isInsideArea,
        'location': GeoPoint(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
        ),
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() => _checkedIn = !_checkedIn);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _checkedIn
                ? "✅ Checked in successfully!"
                : "✅ Checked out successfully!",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _calibrateGPS() async {
    setState(() => _isCalibrating = true);
    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      await AppSettings.openAppSettings(type: AppSettingsType.location);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🧭 Move your phone in figure-8 for better GPS"),
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
    await _startGeofencing();
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ChoiceScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter =
        _currentLocation ??
        (teamPolygon.isNotEmpty
            ? teamPolygon.first
            : const LatLng(10.6, 122.6));

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('OJT Connect'),
        automaticallyImplyLeading: false,
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text("$_fname $_lname"),
              accountEmail: Text(_course),
              currentAccountPicture: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                },
                child: const CircleAvatar(child: Icon(Icons.person, size: 32)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: _logout,
            ),
          ],
        ),
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
                  children: [
                    GestureDetector(
                      onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                      child: const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.person, size: 32),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Welcome, $_fname $_lname!\nTeam: ${_teamName ?? "None"}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ✅ Main Check In / Out Button
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _markAttendance,
                      icon: Icon(
                        _checkedIn ? Icons.logout : Icons.login,
                        size: 28,
                      ),
                      label: Text(
                        _checkedIn ? "Check Out" : "Check In",
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _checkedIn ? Colors.red : Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // ✅ Two small buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SmallButton(
                      icon: Icons.refresh,
                      label: "Restart GPS",
                      onTap: _startGeofencing,
                      isLoading: _isLoading,
                    ),
                    _SmallButton(
                      icon: Icons.my_location,
                      label: "Calibrate",
                      onTap: _calibrateGPS,
                      isLoading: _isCalibrating,
                    ),
                  ],
                ),

                const SizedBox(height: 16),
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
                        PolygonLayer<Object>(
                          polygons: teamPolygon.isNotEmpty
                              ? <Polygon<Object>>[
                                  Polygon<Object>(
                                    points: teamPolygon,
                                    borderColor: Colors.blue,
                                    borderStrokeWidth: 2,
                                    color: Colors.blue.withOpacity(0.3),
                                  ),
                                ]
                              : <Polygon<Object>>[],
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
                  )
                else
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ Small button widget
class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const _SmallButton({
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
            radius: 25,
            backgroundColor: Colors.blue.shade100,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                : Icon(icon, size: 25, color: Colors.blue),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
