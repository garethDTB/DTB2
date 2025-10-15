import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'models/session.dart';
import 'session_details_page.dart';
import 'services/api_service.dart';
import 'auth_state.dart';

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
      final rawSessions = await api.getSessions(widget.wallId, username);
      setState(() {
        _sessions = rawSessions.map((s) => Session.fromJson(s)).toList()
          ..sort((a, b) => b.date.compareTo(a.date)); // newest first
      });
      debugPrint("✅ Loaded ${_sessions.length} sessions for ${widget.wallId}");
    } catch (e) {
      debugPrint("⚠️ Failed to load sessions for ${widget.wallId}: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to load sessions. Please try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final totalSessions = _sessions.length;
    final totalScore = _sessions.fold<int>(0, (sum, s) => sum + (s.score ?? 0));
    final averageScore = totalSessions > 0
        ? (totalScore / totalSessions).toStringAsFixed(1)
        : "0";

    return Scaffold(
      appBar: AppBar(title: Text("${widget.wallId} — Log Book")),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadSessions,
                child: _sessions.isEmpty
                    ? ListView(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          12,
                          12,
                          MediaQuery.of(context).padding.bottom + 12,
                        ),
                        children: const [
                          SizedBox(height: 200),
                          Center(
                            child: Text(
                              "No sessions found.\nStart climbing to log progress!",
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          0,
                          0,
                          MediaQuery.of(context).padding.bottom + 12,
                        ),
                        itemCount: _sessions.length + 1, // +1 for header card
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            // ✅ Summary card at the top
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                              child: ListTile(
                                leading: const Icon(Icons.assessment),
                                title: Text(
                                  "$totalSessions session${totalSessions == 1 ? '' : 's'} in total",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Total score: $totalScore\n"
                                  "Average score per session: $averageScore",
                                ),
                              ),
                            );
                          }

                          final session = _sessions[index - 1];
                          final dateString = DateFormat.yMMMd().format(
                            session.date,
                          );

                          final isToday =
                              session.date.year == today.year &&
                              session.date.month == today.month &&
                              session.date.day == today.day;

                          return Card(
                            color: isToday ? Colors.yellow[100] : null,
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 12,
                            ),
                            child: ListTile(
                              title: Text(
                                "${session.wall} — Score: ${session.score}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text("Date: $dateString"),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SessionDetailsPage(session: session),
                                  ),
                                );

                                if (result is Session) {
                                  setState(() {
                                    final idx = _sessions.indexWhere(
                                      (s) => s.id == result.id,
                                    );
                                    if (idx != -1) {
                                      _sessions[idx] = result;
                                    }
                                  });
                                } else if (result == true) {
                                  await _loadSessions();
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
