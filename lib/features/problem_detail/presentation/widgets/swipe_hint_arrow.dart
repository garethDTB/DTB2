import 'package:flutter/material.dart';

class SwipeHintArrow extends StatelessWidget {
  const SwipeHintArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Icon(Icons.arrow_back, color: Colors.grey),
          Text("Swipe for next/previous problem"),
          Icon(Icons.arrow_forward, color: Colors.grey),
        ],
      ),
    );
  }
}
