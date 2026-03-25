import 'package:flutter/material.dart';
import 'package:tag_battle_royale/widgets/navigation_button.dart';

class CreateLobby extends StatelessWidget {
  const CreateLobby({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create_Lobby"),
      ),
      body: Center(
        child: NavigationButton(displayText: "Lobby", destination: "/Lobby"),
      ),
    );
  }
}