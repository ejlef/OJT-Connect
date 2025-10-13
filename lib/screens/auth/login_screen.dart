import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'choice_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool isAdmin; // true = Admin Login, false = Student Login

  const LoginScreen({super.key, required this.isAdmin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> loginUser() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    // Hash password
    String hashedPassword = sha256.convert(utf8.encode(password)).toString();

    try {
      var query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .where('password', isEqualTo: hashedPassword)
          .where('isAdmin', isEqualTo: widget.isAdmin)
          .get();

      if (query.docs.isNotEmpty) {
        if (widget.isAdmin) {
          Navigator.pushReplacementNamed(context, '/adminDashboard');
        } else {
          Navigator.pushReplacementNamed(context, '/userDashboard');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid email or password")),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ChoiceScreen()),
            );
          },
        ),
        title: Text(widget.isAdmin ? "Admin Login" : "Student Login"),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: loginUser, child: const Text("Login")),
              if (!widget.isAdmin) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(),
                      ),
                    );
                  },
                  child: const Text("Don't have an account? Register"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
