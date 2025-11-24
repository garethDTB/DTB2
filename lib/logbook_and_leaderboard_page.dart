// logbook_and_leaderboard_page.dart
//
// LogBook + Enhanced Leaderboard with:
// - Fast-ish mode (90-day window for most use cases, no backend changes)
// - Filters: 7d / 30d / 90d / 365d / All time
// - Culmination vs Best Session toggle
// - Weekly & Monthly streaks (per username)
// - Interactive chart area:
//     * Top-5 bar chart (tap to inspect)
//     * "My Progress" line chart (tap points)
// - Tap-to-compare two users (long-press rows)
// - "Rising Star" of the last 30 days
// - 🥇🥈🥉 ranking badges
//
// Uses usernames only (no user profile lookups).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import 'models/session.dart';
import 'services/api_service.dart';
import 'auth_state.dart';
import 'session_details_page.dart';

//---------------------------------------------------------
// MAIN WRAPPER WITH TABS
//---------------------------------------------------------
class LogBookAndLeaderboardPage extends StatelessWidget {
  final String wallId;
  const LogBookAndLeaderboardPage({super.key, required this.wallId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(wallId),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Log Book"),
              Tab(text: "Leaderboard"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            LogBookPage(wallId: wallId),
            LeaderboardPage(wallId: wallId),
          ],
        ),
      ),
    );
  }
}

//---------------------------------------------------------
// LOG BOOK PAGE  (same behaviour as before)
//---------------------------------------------------------
class LogBookPage extends StatefulWidget {
  final String wallId;
  const LogBookPage({super.key, required this.wallId});

  @override
  State<LogBookPage> createState() => _LogBookPageState();
}

class _LogBookPageState extends State<LogBookPage> {
  List<Session> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();
    final username = auth.username ?? "guest";

    try {
      final raw = await api.getSessions(widget.wallId, username);
      setState(() {
        _sessions = raw.map((s) => Session.fromJson(s)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      });
    } catch (_) {
      // ignore errors -> empty state shown
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSessions = _sessions.length;
    final totalScore = _sessions.fold<int>(0, (sum, s) => sum + s.score);
    final averageScore = totalSessions > 0
        ? (totalScore / totalSessions).toStringAsFixed(1)
        : "0";
    final today = DateTime.now();

    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _sessions.length + 1,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: ListTile(
                leading: const Icon(Icons.assessment),
                title: Text(
                  "$totalSessions session${totalSessions == 1 ? '' : 's'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Total score: $totalScore\nAverage score: $averageScore",
                ),
              ),
            );
          }

          final s = _sessions[index - 1];
          final dateStr = DateFormat.yMMMd().format(s.date);
          final isToday =
              s.date.year == today.year &&
              s.date.month == today.month &&
              s.date.day == today.day;

          return Card(
            color: isToday ? Colors.yellow[100] : null,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(
                "${s.wall} — Score: ${s.score}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("Date: $dateStr"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailsPage(session: s),
                  ),
                );

                if (result is Session) {
                  setState(() {
                    final idx = _sessions.indexWhere((x) => x.id == result.id);
                    if (idx != -1) _sessions[idx] = result;
                  });
                } else if (result == true) {
                  await _loadSessions();
                }
              },
            ),
          );
        },
      ),
    );
  }
}

//---------------------------------------------------------
// LEADERBOARD PAGE (FAST-ish + STREAKS + CHARTS + COMPARE)
//---------------------------------------------------------
class LeaderboardPage extends StatefulWidget {
  final String wallId;
  const LeaderboardPage({super.key, required this.wallId});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  // All sessions for the wall (full history).
  List<Session> _allSessions = [];

  // Recent sessions (last 90 days) – used for fast default calculations.
  List<Session> _recent90Sessions = [];

  bool _loading = true;
  String? _error;

  // Filter window in days: 7, 30, 90, 365, 9999 (all).
  int _filterDays = 30;

  // true = cumulative (total score in window), false = best single session
  bool _cumulativeMode = true;

  // Chart mode: false = bar (Top 5), true = line (My Progress)
  bool _showLineChart = false;

  // Interactive bar chart touched index
  int? _touchedBarIndex;

  // Interactive line chart touched index
  int? _touchedLineIndex;

  // Compare selection: up to 2 usernames
  final List<String> _compareSelection = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
      _touchedBarIndex = null;
      _touchedLineIndex = null;
      _compareSelection.clear();
    });

    final api = context.read<ApiService>();

    try {
      final raw = await api.getAllSessionsForWall(widget.wallId);

      final sessions = raw.map((e) => Session.fromJson(e)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      final now = DateTime.now();
      final cutoff90 = now.subtract(const Duration(days: 90));
      final recent = sessions.where((s) => s.date.isAfter(cutoff90)).toList();

      if (!mounted) return;
      setState(() {
        _allSessions = sessions;
        _recent90Sessions = recent;
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

  // --------------------------------------------------
  // Filter change with warning for big windows
  // --------------------------------------------------
  Future<void> _onFilterSelected(int days) async {
    if (days == _filterDays) return;

    if (days > 90) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("This might be slow"),
          content: const Text(
            "Loading and crunching a full year or all-time history on a busy wall "
            "can take a little while. Continue?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Continue"),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() {
      _filterDays = days;
      _touchedBarIndex = null;
      _touchedLineIndex = null;
    });
  }

  //--------------------------------------------------
  // Leaderboard data builder for current filter + mode
  //--------------------------------------------------
  List<Map<String, dynamic>> _buildLeaderboard() {
    final now = DateTime.now();

    // For ≤ 90 days, only inspect the recent subset for speed.
    final source = _filterDays <= 90 ? _recent90Sessions : _allSessions;
    final cutoff = now.subtract(Duration(days: _filterDays));

    final window = source.where((s) => s.date.isAfter(cutoff)).toList();

    final totals = <String, int>{};
    final bests = <String, int>{};
    final counts = <String, int>{};

    for (final s in window) {
      final user = s.user;
      final score = s.score;

      totals[user] = (totals[user] ?? 0) + score;
      counts[user] = (counts[user] ?? 0) + 1;

      if (!bests.containsKey(user) || score > bests[user]!) {
        bests[user] = score;
      }
    }

    final entries = <Map<String, dynamic>>[];

    totals.forEach((user, totalScore) {
      final count = counts[user] ?? 0;
      final bestScore = bests[user] ?? 0;
      final metric = _cumulativeMode ? totalScore : bestScore;
      final avgScore = count > 0 ? (totalScore / count) : 0.0;

      entries.add({
        "user": user,
        "display": user, // username only
        "total": totalScore,
        "best": bestScore,
        "avg": avgScore,
        "count": count,
        "metric": metric,
      });
    });

    entries.sort((a, b) => (b["metric"] as num).compareTo(a["metric"] as num));

    return entries;
  }

  // --------------------------------------------------
  // Streak helpers
  // --------------------------------------------------

  /// Weekly streak: consecutive weeks (current week backwards)
  /// where user has ≥1 session.
  int _computeWeeklyStreak(String username) {
    final userSessions = _allSessions.where((s) => s.user == username).toList();
    if (userSessions.isEmpty) return 0;

    // Use Mondays as week keys
    final weekKeys = <DateTime>{};
    for (final s in userSessions) {
      final d = s.date;
      final monday = DateTime(
        d.year,
        d.month,
        d.day,
      ).subtract(Duration(days: d.weekday - 1));
      weekKeys.add(DateTime(monday.year, monday.month, monday.day));
    }

    if (weekKeys.isEmpty) return 0;

    final sorted = weekKeys.toList()..sort((a, b) => a.compareTo(b));

    // Start from the last week key
    DateTime currentWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    int streak = 0;

    while (true) {
      // Find if currentWeek exists in sorted set
      final exists = sorted.any(
        (w) =>
            w.year == currentWeek.year &&
            w.month == currentWeek.month &&
            w.day == currentWeek.day,
      );
      if (!exists) break;

      streak += 1;
      currentWeek = currentWeek.subtract(const Duration(days: 7));
    }

    return streak;
  }

  /// Monthly streak: consecutive months (current month backwards)
  /// where user has ≥1 session.
  int _computeMonthlyStreak(String username) {
    final userSessions = _allSessions.where((s) => s.user == username).toList();
    if (userSessions.isEmpty) return 0;

    final monthKeys = <DateTime>{};
    for (final s in userSessions) {
      final d = s.date;
      monthKeys.add(DateTime(d.year, d.month));
    }

    if (monthKeys.isEmpty) return 0;

    final sorted = monthKeys.toList()..sort((a, b) => a.compareTo(b));

    DateTime now = DateTime.now();
    DateTime currentMonth = DateTime(now.year, now.month);
    int streak = 0;

    while (true) {
      final exists = sorted.any(
        (m) => m.year == currentMonth.year && m.month == currentMonth.month,
      );
      if (!exists) break;

      streak += 1;

      // Go to previous month
      int year = currentMonth.year;
      int month = currentMonth.month - 1;
      if (month == 0) {
        month = 12;
        year -= 1;
      }
      currentMonth = DateTime(year, month);
    }

    return streak;
  }

  // --------------------------------------------------
  // Rising Star (last 30 days, average/session improvement)
  // --------------------------------------------------
  Map<String, dynamic>? _computeRisingStar() {
    if (_allSessions.isEmpty) return null;

    final now = DateTime.now();
    final startLast30 = now.subtract(const Duration(days: 30));
    final startPrev30 = now.subtract(const Duration(days: 60));

    // user → list of sessions
    final byUser = <String, List<Session>>{};
    for (final s in _allSessions) {
      byUser.putIfAbsent(s.user, () => []).add(s);
    }

    String? bestUser;
    double bestDelta = 0.0;
    double bestAvgLast = 0.0;
    double bestAvgPrev = 0.0;
    int bestCountLast = 0;
    int bestCountPrev = 0;

    byUser.forEach((user, sessions) {
      final last30 = sessions
          .where((s) => s.date.isAfter(startLast30))
          .toList();
      final prev30 = sessions
          .where(
            (s) => s.date.isAfter(startPrev30) && !s.date.isAfter(startLast30),
          )
          .toList();

      if (last30.isEmpty || prev30.isEmpty) return;

      final totalLast = last30
          .fold<int>(0, (sum, s) => sum + s.score)
          .toDouble();
      final totalPrev = prev30
          .fold<int>(0, (sum, s) => sum + s.score)
          .toDouble();

      final avgLast = totalLast / last30.length;
      final avgPrev = totalPrev / prev30.length;
      final delta = avgLast - avgPrev;

      if (delta > bestDelta && delta > 0) {
        bestDelta = delta;
        bestUser = user;
        bestAvgLast = avgLast;
        bestAvgPrev = avgPrev;
        bestCountLast = last30.length;
        bestCountPrev = prev30.length;
      }
    });

    if (bestUser == null) return null;

    return {
      "user": bestUser,
      "delta": bestDelta,
      "avgLast": bestAvgLast,
      "avgPrev": bestAvgPrev,
      "sessionsLast": bestCountLast,
      "sessionsPrev": bestCountPrev,
    };
  }

  // --------------------------------------------------
  // Labels
  // --------------------------------------------------
  String _filterLabel() {
    switch (_filterDays) {
      case 7:
        return "Last 7 days";
      case 30:
        return "Last 30 days";
      case 90:
        return "Last 90 days";
      case 365:
        return "Last 365 days";
      default:
        return "All time";
    }
  }

  String _modeLabel() {
    return _cumulativeMode ? "Total score in window" : "Best single session";
  }

  //--------------------------------------------------
  // UI helpers
  //--------------------------------------------------
  Widget _chip(int days, String label) {
    final selected = _filterDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _onFilterSelected(days),
    );
  }

  Widget _modeToggle() {
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        ChoiceChip(
          label: const Text("Cumulative"),
          selected: _cumulativeMode,
          onSelected: (_) => setState(() => _cumulativeMode = true),
        ),
        ChoiceChip(
          label: const Text("Best Session"),
          selected: !_cumulativeMode,
          onSelected: (_) => setState(() => _cumulativeMode = false),
        ),
      ],
    );
  }

  Widget _chartToggle() {
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        ChoiceChip(
          label: const Text("Top 5"),
          selected: !_showLineChart,
          onSelected: (_) => setState(() {
            _showLineChart = false;
            _touchedBarIndex = null;
          }),
        ),
        ChoiceChip(
          label: const Text("My Progress"),
          selected: _showLineChart,
          onSelected: (_) => setState(() {
            _showLineChart = true;
            _touchedLineIndex = null;
          }),
        ),
      ],
    );
  }

  Widget _buildYouVsLeaderCard(
    List<Map<String, dynamic>> entries,
    String? myUsername,
  ) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final leader = entries.first;
    final leaderMetric = leader["metric"] as num? ?? 0;
    final leaderName = leader["display"] as String? ?? leader["user"] as String;

    Map<String, dynamic>? me;
    int myRank = -1;
    if (myUsername != null) {
      for (var i = 0; i < entries.length; i++) {
        if (entries[i]["user"] == myUsername) {
          me = entries[i];
          myRank = i + 1;
          break;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You vs Leader (${_filterLabel()})",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Leader: $leaderName — ${leaderMetric.toStringAsFixed(0)} pts (${_modeLabel()})",
            ),
            const SizedBox(height: 4),
            if (me != null)
              Text(
                "You: ${me["display"] ?? myUsername} — "
                "${(me["metric"] as num? ?? 0).toStringAsFixed(0)} pts "
                "(Rank #$myRank of ${entries.length})",
              )
            else
              const Text("You have no sessions in this window yet."),
            if (me != null)
              Builder(
                builder: (_) {
                  final myMetric = me!["metric"] as num? ?? 0;
                  final diff = leaderMetric - myMetric;
                  if (diff <= 0) {
                    return const Text(
                      "💪 You're tied for the lead or ahead in this window!",
                      style: TextStyle(color: Colors.green),
                    );
                  } else {
                    return Text(
                      "You’re ${diff.toStringAsFixed(0)} pts behind the leader.",
                      style: const TextStyle(color: Colors.blueGrey),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // Top-5 bar chart (interactive)
  // --------------------------------------------------
  Widget _buildTop5Chart(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final top5 = entries.take(5).toList();
    final metrics = top5
        .map((e) => (e["metric"] as num?) ?? 0)
        .map((n) => n.toDouble())
        .toList();
    if (metrics.isEmpty) return const SizedBox.shrink();

    double maxY = metrics.reduce((a, b) => a > b ? a : b);
    if (maxY <= 0) maxY = 1;
    maxY *= 1.1;

    String infoText;
    if (_touchedBarIndex != null &&
        _touchedBarIndex! >= 0 &&
        _touchedBarIndex! < top5.length) {
      final row = top5[_touchedBarIndex!];
      infoText =
          "${row["display"]} — ${(row["metric"] as num).toStringAsFixed(0)} pts";
    } else {
      infoText = "Tap a bar to see their points.";
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Top 5 — ${_filterLabel()} (${_modeLabel()})",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              infoText,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.spot == null) {
                        setState(() {
                          _touchedBarIndex = null;
                        });
                        return;
                      }
                      setState(() {
                        _touchedBarIndex = response.spot!.touchedBarGroupIndex;
                      });
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
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
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= top5.length) {
                            return const SizedBox.shrink();
                          }
                          final name =
                              top5[idx]["display"] as String? ??
                              top5[idx]["user"] as String;
                          final label = name.length > 6
                              ? "${name.substring(0, 6)}…"
                              : name;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < top5.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: ((top5[i]["metric"] as num?) ?? 0).toDouble(),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // Line chart: "My Progress" for current user
  // --------------------------------------------------
  Widget _buildMyProgressChart(String? myUsername) {
    if (myUsername == null) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: _filterDays));

    final mySessions =
        _allSessions
            .where((s) => s.user == myUsername && s.date.isAfter(cutoff))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (mySessions.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            "No sessions for you in ${_filterLabel().toLowerCase()}.",
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < mySessions.length; i++) {
      spots.add(FlSpot(i.toDouble(), mySessions[i].score.toDouble()));
    }

    String infoText;
    if (_touchedLineIndex != null &&
        _touchedLineIndex! >= 0 &&
        _touchedLineIndex! < mySessions.length) {
      final s = mySessions[_touchedLineIndex!];
      final dateStr = DateFormat.MMMd().format(s.date);
      infoText = "$dateStr — ${s.score} pts";
    } else {
      infoText = "Tap a point to inspect that session.";
    }

    double maxY = mySessions
        .map((s) => s.score.toDouble())
        .reduce((a, b) => a > b ? a : b);
    if (maxY <= 0) maxY = 1;
    maxY *= 1.1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "My Progress — ${_filterLabel()}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              infoText,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (spots.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.lineBarSpots == null ||
                          response.lineBarSpots!.isEmpty) {
                        setState(() {
                          _touchedLineIndex = null;
                        });
                        return;
                      }
                      final spot = response.lineBarSpots!.first;
                      setState(() {
                        _touchedLineIndex = spot.x.toInt();
                      });
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
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
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= mySessions.length) {
                            return const SizedBox.shrink();
                          }
                          final d = mySessions[idx].date;
                          final label = DateFormat.Md().format(d);
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      spots: spots,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // Rank leading widget (🥇 🥈 🥉 / #4 etc.)
  // --------------------------------------------------
  Widget _buildRankLeading(int index) {
    switch (index) {
      case 0:
        return const Text(
          "🥇",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        );
      case 1:
        return const Text(
          "🥈",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        );
      case 2:
        return const Text(
          "🥉",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        );
      default:
        return Text(
          "#${index + 1}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        );
    }
  }

  //--------------------------------------------------
  // Tap leaderboard entry → view that user's sessions
  //--------------------------------------------------
  void _openUserSessions(String username) {
    final sessions = _allSessions.where((s) => s.user == username).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserSessionsPage(user: username, sessions: sessions),
      ),
    );
  }

  //--------------------------------------------------
  // Long-press to select up to 2 users for comparison
  //--------------------------------------------------
  void _toggleCompareUser(String username) {
    setState(() {
      if (_compareSelection.contains(username)) {
        _compareSelection.remove(username);
      } else {
        if (_compareSelection.length == 2) {
          // Replace the first selected user
          _compareSelection.removeAt(0);
        }
        _compareSelection.add(username);
      }
    });
  }

  Widget _buildComparisonCard(List<Map<String, dynamic>> entries) {
    if (_compareSelection.length != 2) return const SizedBox.shrink();

    final u1 = _compareSelection[0];
    final u2 = _compareSelection[1];

    final e1 = entries.firstWhere((e) => e["user"] == u1, orElse: () => {});
    final e2 = entries.firstWhere((e) => e["user"] == u2, orElse: () => {});

    if (e1.isEmpty || e2.isEmpty) return const SizedBox.shrink();

    String labelFor(Map<String, dynamic> e) {
      return e["display"] as String? ?? e["user"] as String;
    }

    String metricLabel(Map<String, dynamic> e) {
      return (e["metric"] as num? ?? 0).toStringAsFixed(0);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Compare: ${labelFor(e1)} vs ${labelFor(e2)}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _compareColumn(
                    title: labelFor(e1),
                    metric: metricLabel(e1),
                    total: (e1["total"] as num? ?? 0).toStringAsFixed(0),
                    best: (e1["best"] as num? ?? 0).toStringAsFixed(0),
                    avg: (e1["avg"] as num? ?? 0).toStringAsFixed(1),
                    count: e1["count"] as int? ?? 0,
                    weeklyStreak: _computeWeeklyStreak(u1),
                    monthlyStreak: _computeMonthlyStreak(u1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compareColumn(
                    title: labelFor(e2),
                    metric: metricLabel(e2),
                    total: (e2["total"] as num? ?? 0).toStringAsFixed(0),
                    best: (e2["best"] as num? ?? 0).toStringAsFixed(0),
                    avg: (e2["avg"] as num? ?? 0).toStringAsFixed(1),
                    count: e2["count"] as int? ?? 0,
                    weeklyStreak: _computeWeeklyStreak(u2),
                    monthlyStreak: _computeMonthlyStreak(u2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Tip: long-press another row to change comparison.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareColumn({
    required String title,
    required String metric,
    required String total,
    required String best,
    required String avg,
    required int count,
    required int weeklyStreak,
    required int monthlyStreak,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
          "${_cumulativeMode ? "Total in window" : "Best in window"}: $metric",
        ),
        Text("Sessions: $count"),
        Text("Total: $total"),
        Text("Best: $best"),
        Text("Avg: $avg"),
        Text("Weekly streak: ${weeklyStreak}w"),
        Text("Monthly streak: ${monthlyStreak}m"),
      ],
    );
  }

  Widget _buildStreakCard(String? myUsername) {
    if (myUsername == null) return const SizedBox.shrink();

    final weekly = _computeWeeklyStreak(myUsername);
    final monthly = _computeMonthlyStreak(myUsername);

    if (weekly == 0 && monthly == 0) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text("No active streaks yet. Time to start one!"),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Your Streaks",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Weekly streak: ${weekly} week${weekly == 1 ? '' : 's'}",
                  ),
                  Text(
                    "Monthly streak: ${monthly} month${monthly == 1 ? '' : 's'}",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRisingStarCard() {
    final star = _computeRisingStar();
    if (star == null) return const SizedBox.shrink();

    final user = star["user"] as String;
    final delta = star["delta"] as double;
    final avgLast = star["avgLast"] as double;
    final avgPrev = star["avgPrev"] as double;
    final cLast = star["sessionsLast"] as int;
    final cPrev = star["sessionsPrev"] as int;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.trending_up, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Rising Star (last 30 days)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$user has improved their average score by "
                    "${delta.toStringAsFixed(1)} pts/session.",
                  ),
                  Text(
                    "Prev 30 days: ${avgPrev.toStringAsFixed(1)} over $cPrev session"
                    "${cPrev == 1 ? '' : 's'}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    "Last 30 days: ${avgLast.toStringAsFixed(1)} over $cLast session"
                    "${cLast == 1 ? '' : 's'}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  //--------------------------------------------------
  // BUILD
  //--------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "Failed to load leaderboard:\n$_error",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final auth = context.watch<AuthState>();
    final myUsername = auth.username;
    final leaderboard = _buildLeaderboard();

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 8),

                // Filter chips
                Wrap(
                  spacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _chip(7, "Last week"),
                    _chip(30, "Last 30 days"),
                    _chip(90, "Last 90 days"),
                    _chip(365, "Last year"),
                    _chip(9999, "All time"),
                  ],
                ),

                const SizedBox(height: 8),

                // Mode toggle
                _modeToggle(),

                const SizedBox(height: 8),

                // Chart toggle (Top 5 vs My Progress)
                _chartToggle(),

                const SizedBox(height: 4),

                // You vs Leader
                _buildYouVsLeaderCard(leaderboard, myUsername),

                // Streaks for current user
                _buildStreakCard(myUsername),

                // Rising Star (last 30 days)
                _buildRisingStarCard(),

                // Chart area
                _showLineChart
                    ? _buildMyProgressChart(myUsername)
                    : _buildTop5Chart(leaderboard),

                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      "Leaderboard — ${_filterLabel()}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                // Comparison card (if 2 users selected)
                _buildComparisonCard(leaderboard),
              ],
            ),
          ),

          // Leaderboard list
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final row = leaderboard[index];
              final username = row["user"] as String;
              final selected = _compareSelection.contains(username);

              return Card(
                color: selected ? Colors.blue[50] : null,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: _buildRankLeading(index),
                  title: Text(
                    row["display"] as String? ?? username,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "${_cumulativeMode ? "Total" : "Best"}: "
                    "${(row["metric"] as num? ?? 0).toStringAsFixed(0)}\n"
                    "Sessions: ${row["count"]} | "
                    "Best: ${(row["best"] as num? ?? 0).toStringAsFixed(0)} | "
                    "Avg: ${(row["avg"] as num? ?? 0).toStringAsFixed(1)}",
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _openUserSessions(username);
                  },
                  onLongPress: () {
                    _toggleCompareUser(username);
                  },
                ),
              );
            }, childCount: leaderboard.length),
          ),

          // Bottom padding so last card is nicely scrollable
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ),
        ],
      ),
    );
  }
}

//---------------------------------------------------------
// USER SESSIONS PAGE
//---------------------------------------------------------
class UserSessionsPage extends StatelessWidget {
  final String user;
  final List<Session> sessions;
  const UserSessionsPage({
    super.key,
    required this.user,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(title: Text("$user's Sessions")),
      body: ListView.builder(
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final s = sessions[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(
                "Score: ${s.score}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(dateFmt.format(s.date)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailsPage(session: s),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
