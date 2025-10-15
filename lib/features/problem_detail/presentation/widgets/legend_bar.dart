import 'package:flutter/material.dart';

class LegendBar extends StatelessWidget {
  final int footMode;

  const LegendBar({super.key, required this.footMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _legendItem(Colors.green, "Start"),
          _legendItem(Colors.red, "Finish"),
          _legendItem(Colors.yellow, "Feet (mode $footMode)"),
          _legendItem(Colors.blue, "Intermediate"),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}
