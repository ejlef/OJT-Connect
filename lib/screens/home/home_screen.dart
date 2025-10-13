// import 'package:flutter/material.dart';
// import '../auth/login_screen.dart';
// import '../auth/register_screen.dart';

// class HomeScreen extends StatelessWidget {
//   final bool isAdmin;

//   const HomeScreen({super.key, this.isAdmin = false});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: true,
//       title: 'OJT Connect',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: const LoginScreen(),
//       routes: isAdmin
//           ? {
//               '/login': (context) => const LoginScreen(),
//             }
//           : {
//               '/login': (context) => const LoginScreen(),
//               '/register': (context) => const RegisterScreen(),
//             },
//     );
//   }
// }
