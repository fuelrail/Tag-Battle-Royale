import 'package:flutter/material.dart';
import 'package:tag_battle_royale/widgets/NavigationButton.dart';

class Join_Lobby extends StatelessWidget {
  const Join_Lobby({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Join_Lobby"),
      ),
      body: Center(
        child: NavigationButton(displayText: "Lobby", destination: "/Lobby"),
      ),
    );
  }
}