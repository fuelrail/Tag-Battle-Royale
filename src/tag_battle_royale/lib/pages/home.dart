import 'package:flutter/material.dart';
import 'package:tag_battle_royale/widgets/navigation_button.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
      ),
      body: Center(
        child: Column(
          children: [
            NavigationButton(displayText: "Create Lobby", destination: "/Create_Lobby"),
            NavigationButton(displayText: "Join Lobby", destination: "/Join_Lobby"),
            NavigationButton(displayText: "Map Editor", destination: "/Map_Editor"),
            NavigationButton(displayText: "View Replay", destination: "/Lobby"),
          ]
          
        ,)
      ),
    );
  }
}