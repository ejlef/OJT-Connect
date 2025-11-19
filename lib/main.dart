import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/choice_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/dashboard/admin_dashboard.dart';
import 'screens/dashboard/user_dashboard.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const OJTConnectApp());
}

class OJTConnectApp extends StatelessWidget {
  const OJTConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OJT Connect',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/choice': (context) => const ChoiceScreen(),
        '/login': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>;
          return LoginScreen(isAdmin: args['isAdmin']);
        },
        '/register': (context) => const RegisterScreen(),
        '/adminDashboard': (context) => const AdminDashboard(),
        '/userDashboard': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>;
          return UserDashboard(userId: args['userId']);
        },
      },
    );
  }
}
