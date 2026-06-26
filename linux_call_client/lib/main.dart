// main.dart
//
// Entry point. Shows a tiny "enter your name" screen, then connects to
// the signaling server and moves to the home screen (user list).

import 'package:flutter/material.dart';
import 'signaling_service.dart';
import 'home_screen.dart';

// Your live Render URL goes here.
const String kSignalingServerUrl = 'https://call-app-signaling-server.onrender.com';

void main() {
  runApp(const CallApp());
}

class CallApp extends StatelessWidget {
  const CallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _continue() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final signaling = SignalingService(
      serverUrl: kSignalingServerUrl,
      username: name,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(signaling: signaling)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your name', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _continue, child: const Text('Connect')),
            ],
          ),
        ),
      ),
    );
  }
}
