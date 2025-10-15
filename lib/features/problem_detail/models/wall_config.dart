import '../models/foot_option.dart';
import '../models/hold_point.dart';

class WallConfig {
  final int rows;
  final int cols;
  final int footMode;
  final List<FootOption> footOptions;
  final int minGradeNum;
  final List<HoldPoint> holds;
  final String? wallImagePath;

  const WallConfig({
    required this.rows,
    required this.cols,
    required this.footMode,
    required this.footOptions,
    required this.minGradeNum,
    required this.holds,
    this.wallImagePath,
  });
}
