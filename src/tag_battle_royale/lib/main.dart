
import 'package:flutter/material.dart';
import 'pages/Home.dart';
import 'pages/Create_Lobby.dart';
import 'pages/Join_Lobby.dart';
import 'pages/Map_Editor.dart';
import 'pages/Lobby.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

@override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tag Battle Royale',
      theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Home(),
      routes: {
        "/Home" : (context) => const Home(),
        "/Lobby" : (context) => const Lobby(),
        "/Map_Editor" : (context) => const Map_Editor(),
        "/Create_Lobby" : (context) => const Create_Lobby(),
        "/Join_Lobby" : (context) => const Join_Lobby(),
      },
    );
  }
}
