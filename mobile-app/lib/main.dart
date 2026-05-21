import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mental Healthcare App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Simulated last notification message
  String lastNotification = "Welcome to Mental Healthcare App!";

  // Function to show floating notification
  void showLastNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating, // floats above UI
        margin: const EdgeInsets.all(12),   // keeps away from menu bar
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mental Healthcare App"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Simulate receiving a new notification
            setState(() {
              lastNotification = "You have a new message!";
            });
            showLastNotification(lastNotification);
          },
          child: const Text("Simulate Notification"),
        ),
      ),
    );
  }
}