import 'package:flutter/material.dart';

class TabButton extends StatelessWidget {
  const TabButton({
		super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context){
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color.fromARGB(255, 245, 245, 245),
          border: const Border(
            top: BorderSide(
            color: Color.fromARGB(40, 0, 0, 0),
            width: 1,
            ),
            right: BorderSide(
            color: Color.fromARGB(40, 0, 0, 0),
            width: 1,
            ),
        ),
        ),
        child: Icon(
          icon,
          color: Colors.black,
          size: 20,
        ),
      ),
    );
  }
}