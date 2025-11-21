import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/choice_screen.dart';

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

  // ML Predictions
  List<Map<String, dynamic>> _mlPredictions = [];
  bool _loadingPredictions = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
    _loadQGISZones();
    _loadMLPredictions();
  }

  /// Load teams safely
  Future<void> _loadTeams() async {
    try {
      final snapshot = await _firestore.collection('teams').get();
      setState(() {
        _teams = snapshot.docs
            .map(
              (doc) => DropdownMenuItem(
                value: doc.id,
                child: Text(doc['name'] ?? doc.id),
              ),
            )
            .toList();
        if (!_teams.any((item) => item.value == _selectedTeam)) {
          _selectedTeam = null;
        }
      });
    } catch (e) {
      debugPrint('Error loading teams: $e');
    }
  }

  /// Add a new team
  Future<void> _addTeamDialog() async {
    final TextEditingController teamNameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Team'),
        content: TextField(
          controller: teamNameController,
          decoration: const InputDecoration(labelText: 'Team Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (teamNameController.text.trim().isEmpty) return;
              Navigator.pop(context, teamNameController.text.trim());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final docRef = await _firestore.collection('teams').add({
          'name': result,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _loadTeams();
        setState(() => _selectedTeam = docRef.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Team added successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error adding team: $e')));
      }
    }
  }

  /// Delete selected team and update users
  Future<void> _deleteTeam() async {
    if (_selectedTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please select a team to delete')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Team"),
        content: const Text(
          "Are you sure you want to delete this team? All users in this team will have their team assignment cleared.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final usersSnapshot = await _firestore
            .collection('users')
            .where('teamId', isEqualTo: _selectedTeam)
            .get();

        for (var userDoc in usersSnapshot.docs) {
          await _firestore.collection('users').doc(userDoc.id).update({
            'teamId': null,
          });
        }

        await _firestore.collection('teams').doc(_selectedTeam).delete();
        await _loadTeams();
        setState(() => _selectedTeam = null);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Team deleted and users updated!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting team: $e')));
      }
    }
  }

  /// Load GeoJSON zones
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

  /// Load ML predictions
  Future<void> _loadMLPredictions() async {
    try {
      final snapshot = await _firestore.collection('ml_predictions').get();

      setState(() {
        _mlPredictions =
            snapshot.docs.map((doc) => doc.data()).toList();
        _mlPredictions.sort((a, b) =>
            b['lateProbability'].compareTo(a['lateProbability']));
        _loadingPredictions = false;
      });
    } catch (e) {
      debugPrint('Error loading ML predictions: $e');
      setState(() => _loadingPredictions = false);
    }
  }

  /// Handle map tap to select polygon
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ No zone found at tapped location')),
    );
  }

  /// Point in polygon check
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
    return (intersectCount % 2) == 1;
  }

  /// Save polygon bounds to Firestore
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

  /// Logout with confirmation
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseAuth.instance.signOut();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const ChoiceScreen()),
          (route) => false,
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
      }
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
            icon: const Icon(Icons.analytics),
            tooltip: 'Refresh Predictions',
            onPressed: () {
              setState(() => _loadingPredictions = true);
              _loadMLPredictions();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _teams.any((item) => item.value == _selectedTeam)
                        ? _selectedTeam
                        : null,
                    items: _teams,
                    hint: const Text('Select Team'),
                    onChanged: (value) => setState(() => _selectedTeam = value),
                    decoration: const InputDecoration(
                      labelText: 'Select Team',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addTeamDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _deleteTeam,
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
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
          // ML Predictions Section
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Predicted At-Risk Students',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _loadingPredictions
                    ? const Center(child: CircularProgressIndicator())
                    : _mlPredictions.isEmpty
                        ? const Text('No ML predictions available.')
                        : SizedBox(
                            height: 200,
                            child: ListView.builder(
                              itemCount: _mlPredictions.length,
                              itemBuilder: (context, index) {
                                final student = _mlPredictions[index];
                                double lateProb = student['lateProbability'];
                                double absentProb = student['absentProbability'];
                                Color statusColor = lateProb > 0.7
                                    ? Colors.red
                                    : lateProb > 0.4
                                        ? Colors.orange
                                        : Colors.green;

                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: statusColor,
                                      child: Text(
                                        student['studentId']
                                            .substring(0, 2)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    title: Text(student['studentName'] ??
                                        student['studentId']),
                                    subtitle: Text(
                                        'Late: ${(lateProb * 100).toStringAsFixed(1)}% | Absent: ${(absentProb * 100).toStringAsFixed(1)}%'),
                                  ),
                                );
                              },
                            ),
                          ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
