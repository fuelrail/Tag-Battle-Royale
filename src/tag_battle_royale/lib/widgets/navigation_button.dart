import 'package:flutter/material.dart';

class NavigationButton extends StatelessWidget {
  final String displayText;
  final String destination;

  const NavigationButton({
    super.key,
    required this.displayText,
    required this.destination});

  @override
  Widget build(BuildContext context){
    return ElevatedButton(
      child: Text(displayText),
      onPressed: (){
        Navigator.pushNamed(context, destination);
      },
    );
  
  }
}