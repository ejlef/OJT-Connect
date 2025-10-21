import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/choice_screen.dart'; // ✅ Make sure this import is correct

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final MapController _mapController = MapController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<DropdownMenuItem<String>> _teams = [];
  String? _selectedTeam;
  GeoJsonParser geoJsonParser = GeoJsonParser();
  List<Polygon> polygons = [];
  Polygon? _selectedPolygon;

  @override
  void initState() {
    super.initState();
    _loadTeams();
    _loadQGISZones();
  }

  /// 🔹 Load teams from Firestore
  Future<void> _loadTeams() async {
    try {
      final snapshot = await _firestore.collection('teams').get();

      if (snapshot.docs.isEmpty) {
        await _createDefaultTeams();
        return _loadTeams();
      }

      setState(() {
        _teams = snapshot.docs
            .map(
              (doc) => DropdownMenuItem(
                value: doc.id,
                child: Text(doc['name'] ?? doc.id),
              ),
            )
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading teams: $e');
    }
  }

  /// 🔹 Create default teams if Firestore is empty
  Future<void> _createDefaultTeams() async {
    final defaultTeams = [
      {'name': 'Team A'},
      {'name': 'Team B'},
      {'name': 'Team C'},
    ];
    for (var team in defaultTeams) {
      await _firestore.collection('teams').add(team);
    }
  }

  /// 🔹 Load GeoJSON zones
  Future<void> _loadQGISZones() async {
    try {
      const url =
          'https://raw.githubusercontent.com/ejlef/OJT_Connect_ojtzone/refs/heads/main/ojtzone.geojson';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        geoJsonParser.parseGeoJson(jsonDecode(response.body));
        setState(() {
          polygons = geoJsonParser.polygons;
        });
      }
    } catch (e) {
      debugPrint('Error loading QGIS data: $e');
    }
  }

  /// 🔹 Handle map tap to select polygon
  void _onMapTap(LatLng tapPoint) {
    for (var polygon in polygons) {
      if (_pointInPolygon(tapPoint, polygon.points)) {
        setState(() {
          _selectedPolygon = polygon;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('✅ Zone selected!')));
        return;
      }
    }

    // If no polygon tapped
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ No zone found at tapped location')),
    );
  }

  /// 🔹 Check if point is inside polygon (ray-casting algorithm)
  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0; j < polygon.length - 1; j++) {
      var a = polygon[j];
      var b = polygon[j + 1];
      if (((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1; // inside if odd
  }

  /// 🔹 Save selected polygon’s bounds to Firestore
  Future<void> _setTeamZone() async {
    if (_selectedTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please select a team first')),
      );
      return;
    }
    if (_selectedPolygon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please tap a zone on the map')),
      );
      return;
    }

    final firstPoint = _selectedPolygon!.points.first;
    final bounds = LatLngBounds(firstPoint, firstPoint);

    for (final point in _selectedPolygon!.points) {
      bounds.extend(point);
    }

    await _firestore.collection('teams').doc(_selectedTeam).set({
      'zone': {
        'southWest': {
          'lat': bounds.southWest.latitude,
          'lng': bounds.southWest.longitude,
        },
        'northEast': {
          'lat': bounds.northEast.latitude,
          'lng': bounds.northEast.longitude,
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Team zone saved successfully!')),
    );
  }

  /// 🚪 Logout confirmation dialog
  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout Confirmation"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ChoiceScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Teams',
            onPressed: _loadTeams,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: DropdownButtonFormField<String>(
              value: _selectedTeam,
              items: _teams,
              hint: const Text('Select Team'),
              onChanged: (value) => setState(() => _selectedTeam = value),
              decoration: const InputDecoration(
                labelText: 'Select Team',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(10.5935, 122.6009),
                initialZoom: 16,
                onTap: (_, point) => _onMapTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (polygons.isNotEmpty)
                  PolygonLayer(
                    polygons: polygons.map((polygon) {
                      bool isSelected = polygon == _selectedPolygon;
                      return Polygon(
                        points: polygon.points,
                        color: isSelected
                            ? Colors.green.withOpacity(0.6)
                            : Colors.blue.withOpacity(0.3),
                        borderStrokeWidth: 2,
                        borderColor: isSelected ? Colors.green : Colors.blue,
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: _setTeamZone,
              icon: const Icon(Icons.save),
              label: const Text('Save Selected Zone for Team'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 20,
                ),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
