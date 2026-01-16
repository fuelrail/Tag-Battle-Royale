import 'package:flutter/material.dart';
import 'package:tag_battle_royale/widgets/NavigationButton.dart';

class Create_Lobby extends StatelessWidget {
  const Create_Lobby({super.key});

  @override
  Widget build(BuildContext context) {
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