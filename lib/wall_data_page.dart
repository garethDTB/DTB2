import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import 'services/api_service.dart';
import 'auth_state.dart';

class WallDataPage extends StatefulWidget {
  final String wallId;

  const WallDataPage({super.key, required this.wallId});

  @override
  State<WallDataPage> createState() => _WallDataPageState();
}

class _WallDataPageState extends State<WallDataPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _problems = [];
  List<Map<String, dynamic>> _myTicks = [];
  List<Map<String, dynamic>> _wallTicks = [];

  final List<String> _gradeOrder = const [
    "4a",
    "4a+",
    "4b",
    "4b+",
    "4c",
    "4c+",
    "5a",
    "5a+",
    "5b",
    "5b+",
    "5c",
    "5c+",
    "6a",
    "6a+",
    "6b",
    "6b+",
    "6c",
    "6c+",
    "7a",
    "7a+",
    "7b",
    "7b+",
    "7c",
    "7c+",
    "8a",
    "8a+",
    "8b",
    "8b+",
    "8c",
    "8c+",
    "Project",
  ];

  @override
  void initState() {
    super.initState();
    _loadWallData();
  }

  Future<void> _loadWallData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthState>();
      final username = auth.username ?? "guest";

      final rawProblems = await api.getWallProblems(widget.wallId);
      final rawSessions = await api.getSessions(widget.wallId, username);
      final rawWallTicks = await api.getWallTicks(widget.wallId);

      final myTicks = <Map<String, dynamic>>[];

      for (final session in rawSessions) {
        final sent = session["Sent"];
        if (sent is List) {
          for (final tick in sent) {
            if (tick is Map) {
              myTicks.add(Map<String, dynamic>.from(tick));
            }
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _problems = rawProblems
            .map<Map<String, dynamic>>((p) => Map<String, dynamic>.from(p))
            .toList();

        _myTicks = myTicks;

        _wallTicks = rawWallTicks
            .map<Map<String, dynamic>>((t) => Map<String, dynamic>.from(t))
            .toList();

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _field(Map<String, dynamic> item, List<String> names) {
    for (final name in names) {
      final value = item[name];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return "";
  }

  String _problemName(Map<String, dynamic> problem) {
    return _field(problem, ["Problem", "Name", "problem", "name", "Title"]);
  }

  String _problemGrade(Map<String, dynamic> problem) {
    return _field(problem, ["Grade", "grade"]);
  }

  String _tickProblemName(Map<String, dynamic> tick) {
    return _field(tick, ["Problem", "Name", "problem", "name"]);
  }

  String _tickGrade(Map<String, dynamic> tick) {
    return _field(tick, ["Grade", "grade"]);
  }

  bool _isBenchmark(Map<String, dynamic> problem) {
    final benchmark = _field(problem, ["Benchmark", "benchmark"]);

    if (benchmark.toLowerCase() == "true" || benchmark == "1") {
      return true;
    }

    final comment = _field(problem, ["Comment", "comment"]);
    final name = _problemName(problem);

    return comment.toLowerCase().contains("benchmark") ||
        name.toLowerCase().contains("benchmark");
  }

  int _gradeIndex(String grade) {
    final idx = _gradeOrder.indexWhere(
      (g) => g.toLowerCase() == grade.toLowerCase(),
    );
    return idx == -1 ? 999 : idx;
  }

  Map<String, int> _gradeDistribution(List<Map<String, dynamic>> items) {
    final map = <String, int>{};

    for (final item in items) {
      final grade = _problemGrade(item);
      if (grade.isEmpty) continue;
      map[grade] = (map[grade] ?? 0) + 1;
    }

    final sorted = Map.fromEntries(
      map.entries.toList()
        ..sort((a, b) => _gradeIndex(a.key).compareTo(_gradeIndex(b.key))),
    );

    return sorted;
  }

  Map<String, int> _myGradeDistribution() {
    final map = <String, int>{};

    final uniqueTicksByProblem = <String, Map<String, dynamic>>{};

    for (final tick in _myTicks) {
      final name = _tickProblemName(tick);
      if (name.isEmpty) continue;
      uniqueTicksByProblem[name] = tick;
    }

    for (final tick in uniqueTicksByProblem.values) {
      var grade = _tickGrade(tick);

      if (grade.isEmpty) {
        final problemName = _tickProblemName(tick);
        final problem = _problems.firstWhere(
          (p) => _problemName(p) == problemName,
          orElse: () => {},
        );
        if (problem.isNotEmpty) {
          grade = _problemGrade(problem);
        }
      }

      if (grade.isEmpty) continue;
      map[grade] = (map[grade] ?? 0) + 1;
    }

    final sorted = Map.fromEntries(
      map.entries.toList()
        ..sort((a, b) => _gradeIndex(a.key).compareTo(_gradeIndex(b.key))),
    );

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final username = auth.username ?? "guest";

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _problems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "Failed to load wall data:\n$_error",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalProblems = _problems.length;

    final benchmarks = _problems.where(_isBenchmark).toList();
    final totalBenchmarks = benchmarks.length;

    final problemsSetByMe = _problems.where((p) {
      final setter = _field(p, ["Setter", "setter", "User", "user"]);
      return setter.toLowerCase() == username.toLowerCase();
    }).length;

    final setPercent = totalProblems == 0
        ? 0.0
        : (problemsSetByMe / totalProblems) * 100;

    final myTickedNames = _myTicks
        .map(_tickProblemName)
        .where((p) => p.isNotEmpty)
        .toSet();

    final myUniqueClimbs = myTickedNames.length;
    final myTotalTicks = _myTicks.length;

    final myUniquePercent = totalProblems == 0
        ? 0.0
        : (myUniqueClimbs / totalProblems) * 100;

    final benchmarksDone = benchmarks.where((p) {
      final name = _problemName(p);
      return myTickedNames.contains(name);
    }).length;

    final totalWallTicks = _wallTicks.fold<int>(0, (sum, t) {
      final count = t["Count"] ?? t["count"] ?? 0;
      if (count is int) return sum + count;
      final parsed = int.tryParse(count.toString()) ?? 0;
      return sum + parsed;
    });

    final wallGradeDist = _gradeDistribution(_problems);
    final myGradeDist = _myGradeDistribution();

    return RefreshIndicator(
      onRefresh: _loadWallData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        children: [
          _sectionCard(
            icon: Icons.person,
            title: "My Wall Stats",
            children: [
              _statRow(
                "Unique climbs done",
                "$myUniqueClimbs / $totalProblems (${myUniquePercent.toStringAsFixed(1)}%)",
              ),
              _statRow("Total ticks", "$myTotalTicks"),
              _statRow("Benchmarks done", "$benchmarksDone / $totalBenchmarks"),
              _statRow(
                "Problems set by me",
                "$problemsSetByMe / $totalProblems (${setPercent.toStringAsFixed(1)}%)",
              ),
            ],
          ),
          _sectionCard(
            icon: Icons.analytics,
            title: "Wall Stats",
            children: [
              _statRow("Total problems", "$totalProblems"),
              _statRow("Benchmarks", "$totalBenchmarks"),
              _statRow("Total wall ticks", "$totalWallTicks"),
            ],
          ),
          _sectionCard(
            icon: Icons.bar_chart,
            title: "Wall Grade Distribution",
            children: [
              SizedBox(
                height: 260,
                child: _WallGradeDistributionChart(
                  wallGradeDist: wallGradeDist,
                ),
              ),
            ],
          ),
          _sectionCard(
            icon: Icons.check_circle,
            title: "My Completion by Grade",
            children: [
              SizedBox(
                height: 260,
                child: _MyCompletionByGradeChart(
                  wallGradeDist: wallGradeDist,
                  myGradeDist: myGradeDist,
                ),
              ),
            ],
          ),
          _sectionCard(
            icon: Icons.list,
            title: "Grades",
            children: [
              ...wallGradeDist.keys.map((grade) {
                final wallCount = wallGradeDist[grade] ?? 0;
                final myCount = myGradeDist[grade] ?? 0;
                return _statRow(grade, "Wall: $wallCount   Me: $myCount");
              }),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _WallGradeDistributionChart extends StatelessWidget {
  final Map<String, int> wallGradeDist;

  const _WallGradeDistributionChart({required this.wallGradeDist});

  @override
  Widget build(BuildContext context) {
    final grades = wallGradeDist.keys.toList();

    if (grades.isEmpty) {
      return const Center(child: Text("No grade data found."));
    }

    final maxY = [
      ...wallGradeDist.values,
      1,
    ].reduce((a, b) => a > b ? a : b).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY + 2,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final grade = grades[group.x.toInt()];

              return BarTooltipItem(
                "$grade\nWall: ${rod.toY.toInt()}",
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();

                if (idx < 0 || idx >= grades.length) {
                  return const SizedBox.shrink();
                }

                final grade = grades[idx].toLowerCase();

                final showLabel =
                    grade == "4a" ||
                    grade == "5a" ||
                    grade == "6a" ||
                    grade == "7a" ||
                    grade == "8a";

                if (!showLabel) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    grades[idx],
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < grades.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (wallGradeDist[grades[i]] ?? 0).toDouble(),
                  width: 10,
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MyCompletionByGradeChart extends StatelessWidget {
  final Map<String, int> wallGradeDist;
  final Map<String, int> myGradeDist;

  const _MyCompletionByGradeChart({
    required this.wallGradeDist,
    required this.myGradeDist,
  });

  @override
  Widget build(BuildContext context) {
    final grades = wallGradeDist.keys.toList();

    if (grades.isEmpty) {
      return const Center(child: Text("No grade data found."));
    }

    return BarChart(
      BarChartData(
        maxY: 100,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final grade = grades[group.x.toInt()];
              final wallCount = wallGradeDist[grade] ?? 0;
              final myCount = myGradeDist[grade] ?? 0;

              return BarTooltipItem(
                "$grade\n$myCount / $wallCount climbed\n${rod.toY.toStringAsFixed(1)}%",
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                return Text(
                  "${value.toInt()}%",
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();

                if (idx < 0 || idx >= grades.length) {
                  return const SizedBox.shrink();
                }

                final grade = grades[idx].toLowerCase();

                final showLabel =
                    grade == "4a" ||
                    grade == "5a" ||
                    grade == "6a" ||
                    grade == "7a" ||
                    grade == "8a";

                if (!showLabel) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    grades[idx],
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < grades.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _completionPercent(grades[i]),
                  width: 10,
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
        ],
      ),
    );
  }

  double _completionPercent(String grade) {
    final wallCount = wallGradeDist[grade] ?? 0;
    final myCount = myGradeDist[grade] ?? 0;

    if (wallCount == 0) return 0;

    return (myCount / wallCount) * 100;
  }
}
