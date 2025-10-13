import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fnameController = TextEditingController();
  final TextEditingController _lnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _schoolIdController = TextEditingController();
  final TextEditingController _courseController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedBirthday;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> registerUser() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    String fname = _fnameController.text.trim();
    String lname = _lnameController.text.trim();
    String ageText = _ageController.text.trim();
    String schoolId = _schoolIdController.text.trim();
    String course = _courseController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        fname.isEmpty ||
        lname.isEmpty ||
        _selectedGender == null ||
        ageText.isEmpty ||
        _selectedBirthday == null ||
        schoolId.isEmpty ||
        course.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    int age = int.tryParse(ageText) ?? 0;

    try {
      var existingUser = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (existingUser.docs.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Email already exists")));
        return;
      }

      // Hash password
      String hashedPassword = sha256.convert(utf8.encode(password)).toString();

      await _firestore.collection('users').add({
        'email': email,
        'password': hashedPassword,
        'fname': fname,
        'lname': lname,
        'gender': _selectedGender,
        'age': age,
        'birthday': Timestamp.fromDate(_selectedBirthday!),
        'schoolId': schoolId,
        'course': course,
        'isAdmin': false,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account created successfully!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(isAdmin: false),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _pickBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const LoginScreen(isAdmin: false),
              ),
            );
          },
        ),
        title: const Text("Student Register"),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _fnameController,
                decoration: const InputDecoration(labelText: "First Name"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lnameController,
                decoration: const InputDecoration(labelText: "Last Name"),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _selectedGender,
                items: const [
                  DropdownMenuItem(value: "Male", child: Text("Male")),
                  DropdownMenuItem(value: "Female", child: Text("Female")),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                decoration: const InputDecoration(labelText: "Gender"),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: "Age"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

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
                    child: const Text("Pick Date"),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _schoolIdController,
                decoration: const InputDecoration(labelText: "School ID"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _courseController,
                decoration: const InputDecoration(labelText: "Course"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: registerUser,
                child: const Text("Register"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
