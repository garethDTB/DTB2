class HoldPoint {
  final String? id; // optional raw id, e.g. "hold80"
  final String label; // converted label, e.g. "B5"
  final double x;
  final double y;

  const HoldPoint({
    this.id, // optional
    required this.label, // required
    required this.x,
    required this.y,
  });
}
