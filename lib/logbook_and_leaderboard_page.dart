// logbook_and_leaderboard_page.dart
//
// LogBook + Enhanced Leaderboard with:
// - Fast default mode (last 90 days window)
// - Filters: 7d / 30d / 90d / 365d / All time
// - Culmination vs Best Session toggle
// - Top-5 bar chart
// - "You vs Leader" comparison card
// - 🥇🥈🥉 ranking badges

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
      // swallow errors -> show empty with 0 stats
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
// LEADERBOARD PAGE (FAST MODE + CHART + COMPARISON)
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

  // Recent sessions (last 90 days) – used for fast default mode.
  List<Session> _recent90Sessions = [];

  // username → display name
  final Map<String, String> _displayNames = {};

  bool _loading = true;
  String? _error;

  // Filter window in days: 7, 30, 90, 365, 9999
  int _filterDays = 30;

  // true = cumulative (total score in window), false = best single session
  bool _cumulativeMode = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = context.read<ApiService>();

    try {
      final raw = await api.getAllSessionsForWall(widget.wallId);

      final sessions = raw.map((e) => Session.fromJson(e)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      final now = DateTime.now();
      final cutoff90 = now.subtract(const Duration(days: 90));
      final recent = sessions.where((s) => s.date.isAfter(cutoff90)).toList();

      final usernames = sessions.map((s) => s.user).toSet();

      if (!mounted) return;
      setState(() {
        _allSessions = sessions;
        _recent90Sessions = recent;
        _loading = false;
      });

      // Fetch display names in the background (non-blocking for UI).
      _fetchDisplayNames(api, usernames);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchDisplayNames(ApiService api, Set<String> usernames) async {
    try {
      final futures = usernames.map((u) async {
        try {
          final userResp = await api.getUser(u);
          final dn = userResp["display_name"] as String? ?? u;
          return MapEntry(u, dn);
        } catch (_) {
          return MapEntry(u, u);
        }
      }).toList();

      final results = await Future.wait(futures);
      if (!mounted) return;

      setState(() {
        for (final e in results) {
          _displayNames[e.key] = e.value;
        }
      });
    } catch (_) {
      // ignore name fetch errors silently
    }
  }

  // --------------------------------------------------
  // Filter change with heavy warning for big windows
  // --------------------------------------------------
  Future<void> _onFilterSelected(int days) async {
    if (days == _filterDays) return;

    if (days > 90) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("This might be slow"),
          content: const Text(
            "Loading and crunching a full year or all-time history on a busy board "
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

    setState(() => _filterDays = days);
  }

  //--------------------------------------------------
  // Build leaderboard data for current filter + mode
  //--------------------------------------------------
  List<Map<String, dynamic>> _buildLeaderboard() {
    final now = DateTime.now();

    // Fast path: for ≤ 90 days, only look at recent sessions.
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
        "display": _displayNames[user] ?? user,
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
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(enabled: true),
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

                // You vs Leader
                _buildYouVsLeaderCard(leaderboard, myUsername),

                // Top-5 chart
                _buildTop5Chart(leaderboard),

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
              ],
            ),
          ),

          // Leaderboard list
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final row = leaderboard[index];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: _buildRankLeading(index),
                  title: Text(
                    row["display"] as String? ?? row["user"] as String,
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
                    _openUserSessions(row["user"] as String);
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
