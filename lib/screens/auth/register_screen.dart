import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fnameController = TextEditingController();
  final TextEditingController _lnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _schoolIdController = TextEditingController();
  final TextEditingController _courseController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedBirthday;
  List<DropdownMenuItem<String>> _teamItems = [];
  String? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final snapshot = await _firestore.collection('teams').get();
    setState(() {
      _teamItems = snapshot.docs
          .map(
            (doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name'])),
          )
          .toList();
    });
  }

  Future<void> _pickBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedBirthday = picked);
  }

  Future<void> registerUser() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        _fnameController.text.isEmpty ||
        _lnameController.text.isEmpty ||
        _selectedGender == null ||
        _ageController.text.isEmpty ||
        _selectedBirthday == null ||
        _schoolIdController.text.isEmpty ||
        _courseController.text.isEmpty ||
        _selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all fields")),
      );
      return;
    }

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      User? user = userCredential.user;

      if (user != null) {
        String fullName =
            "${_fnameController.text.trim()} ${_lnameController.text.trim()}";
        await user.updateDisplayName(fullName);
        await user.sendEmailVerification();

        await _firestore.collection("users").doc(user.uid).set({
          "email": email,
          "fname": _fnameController.text.trim(),
          "lname": _lnameController.text.trim(),
          "gender": _selectedGender,
          "age": int.parse(_ageController.text),
          "birthday": Timestamp.fromDate(_selectedBirthday!),
          "schoolId": _schoolIdController.text.trim(),
          "course": _courseController.text.trim(),
          "teamId": _selectedTeamId,
          "isAdmin": false,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Hello $fullName, account created! Please verify your email before login",
            ),
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen(isAdmin: false)),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Register"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _fnameController,
              decoration: const InputDecoration(labelText: "First Name"),
            ),
            TextField(
              controller: _lnameController,
              decoration: const InputDecoration(labelText: "Last Name"),
            ),
            DropdownButtonFormField(
              value: _selectedGender,
              items: const [
                DropdownMenuItem(value: "Male", child: Text("Male")),
                DropdownMenuItem(value: "Female", child: Text("Female")),
              ],
              onChanged: (val) => setState(() => _selectedGender = val),
              decoration: const InputDecoration(labelText: "Gender"),
            ),
            TextField(
              controller: _ageController,
              decoration: const InputDecoration(labelText: "Age"),
              keyboardType: TextInputType.number,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedBirthday == null
                        ? "No birthday selected"
                        : "Birthday: ${_selectedBirthday!.toLocal().toString().split(' ')[0]}",
                  ),
                ),
                TextButton(
                  onPressed: _pickBirthday,
                  child: const Text("Pick Birthday"),
                ),
              ],
            ),
            TextField(
              controller: _schoolIdController,
              decoration: const InputDecoration(labelText: "School ID"),
            ),
            TextField(
              controller: _courseController,
              decoration: const InputDecoration(labelText: "Course"),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            DropdownButtonFormField(
              value: _selectedTeamId,
              items: _teamItems,
              hint: const Text("Select Team"),
              onChanged: (val) => setState(() => _selectedTeamId = val),
              decoration: const InputDecoration(labelText: "Team"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: registerUser,
              child: const Text("Register"),
            ),
          ],
        ),
      ),
    );
  }
}
