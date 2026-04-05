import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    debugPrint("✅ Firebase initialized successfully");
    
    // Wait a moment for auth to settle
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Check if already signed in
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint("⚠️ No user signed in, attempting anonymous sign-in...");
      UserCredential cred = await FirebaseAuth.instance.signInAnonymously();
      debugPrint("✅ Anonymous user signed in: ${cred.user?.uid}");
    } else {
      debugPrint("✅ User already signed in: ${currentUser.uid}");
      debugPrint("Email: ${currentUser.email}, Anonymous: ${currentUser.isAnonymous}");
    }
  } catch(e) {
    debugPrint("❌ Firebase error: $e");
    // Try to sign in again if it failed
    try {
      await FirebaseAuth.instance.signInAnonymously();
      debugPrint("✅ Retry sign-in successful");
    } catch (retryError) {
      debugPrint("❌ Retry sign-in failed: $retryError");
    }
  }
  runApp(const GeoRideApp());
}

class GeoRideApp extends StatelessWidget {
  const GeoRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoRide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
