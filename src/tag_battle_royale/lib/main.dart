import 'package:flutter/material.dart';
import 'package:tag_battle_royale/widgets/google_maps_viewer.dart';
import 'pages/home.dart';
import 'pages/Create_Lobby.dart';
import 'pages/join_lobby.dart';
import 'pages/map_editor.dart';
import 'pages/lobby.dart';

void main(){
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

@override
  Widget build(BuildContext context){
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
        "/Map_Editor" : (context) => const MapEditor(),
        "/Create_Lobby" : (context) => const CreateLobby(),
        "/Join_Lobby" : (context) => const JoinLobby(),
        "/Create_Map" : (context) => const GoogleMaps(),
      },
    );
  }
}