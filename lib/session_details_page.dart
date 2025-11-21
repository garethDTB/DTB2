import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/session.dart';
import 'services/api_service.dart';
import 'auth_state.dart';
import 'hold_utils.dart';

class SessionDetailsPage extends StatefulWidget {
  final Session session;

  const SessionDetailsPage({super.key, required this.session});

  @override
  State<SessionDetailsPage> createState() => _SessionDetailsPageState();
}

class _SessionDetailsPageState extends State<SessionDetailsPage>
    with TickerProviderStateMixin {
  late Session _session;
  String gradeMode = "french";

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _loadGradeMode();
  }

  Future<void> _loadGradeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      gradeMode = prefs.getString("gradeMode") ?? "french";
    });
  }

  void _showMessage(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // DELETE (no undo)
  // --------------------------------------------------------------------------
  Future<void> _deleteProblem(int index, String grade) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Problem"),
        content: const Text(
          "Are you sure you want to permanently delete this problem from your logbook?\n\n"
          "⚠️ This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthState>();

      final reduction = getPointsForGrade(grade);

      final updatedJson = await api.deleteSentProblem(
        _session.wall,
        _session.id,
        index,
        auth.username ?? "guest",
        reduction: reduction,
      );

      setState(() {
        _session = Session.fromJson(updatedJson);

        // Score cannot be negative
        if (_session.score < 0) {
          _session = Session(
            id: _session.id,
            user: _session.user,
            wall: _session.wall,
            date: _session.date,
            score: 0,
            attempts: _session.attempts,
            sent: _session.sent,
          );
        }

        // If no sent problems left → score = 0
        if (_session.sent.isEmpty) {
          _session = Session(
            id: _session.id,
            user: _session.user,
            wall: _session.wall,
            date: _session.date,
            score: 0,
            attempts: _session.attempts,
            sent: _session.sent,
          );
        }
      });

      _showMessage("Problem deleted successfully");
    } catch (e) {
      _showMessage("Failed to delete: $e", error: true);
    }
  }

  // --------------------------------------------------------------------------
  // Grade label conversion
  // --------------------------------------------------------------------------
  String _displayProblemName(SentProblem p) {
    if (gradeMode != "vgrade") return p.problem;

    final v = frenchToVGrade(p.grade);
    final pattern = RegExp(r"(\\s*\\(?${RegExp.escape(p.grade)}\\)?)\$");

    return p.problem.replaceAll(pattern, " $v");
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final bool isOwner = auth.username == _session.user;

    final attempts = _session.attempts;
    final sent = _session.sent;

    final totalAttempts =
        attempts.fold<int>(0, (sum, a) => sum + a.attempts) +
        sent.fold<int>(0, (sum, s) => sum + s.attempts);

    final totalSent = sent.length;

    final avgAttempts = totalSent > 0
        ? (totalAttempts / totalSent).toStringAsFixed(1)
        : "0";

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${_session.wall} — ${DateFormat.yMMMd().format(_session.date)}",
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ------------------- SUMMARY -------------------
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Score: ${_session.score}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("Problems sent: $totalSent"),
                    Text("Total attempts: $totalAttempts"),
                    Text("Avg attempts per send: $avgAttempts"),
                  ],
                ),
              ),
            ),

            // ------------------- ATTEMPTS -------------------
            if (attempts.isNotEmpty)
              ExpansionTile(
                title: const Text(
                  "Attempts",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                children: attempts
                    .map(
                      (a) => ListTile(
                        title: Text(a.problem),
                        trailing: Text("${a.attempts} tries"),
                      ),
                    )
                    .toList(),
              ),

            // ------------------- SENT PROBLEMS -------------------
            ExpansionTile(
              initiallyExpanded: true,
              title: const Text(
                "Sent Problems",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              children: sent.isNotEmpty
                  ? List.generate(sent.length, (index) {
                      final s = sent[index];

                      return AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: ListTile(
                            tileColor: Colors.grey[50],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            title: Text(_displayProblemName(s)),
                            subtitle: Text("Attempts: ${s.attempts}"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(
                                    gradeMode == "vgrade"
                                        ? frenchToVGrade(s.grade)
                                        : s.grade,
                                  ),
                                ),

                                if (isOwner)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () =>
                                        _deleteProblem(index, s.grade),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    })
                  : const [
                      ListTile(
                        title: Text("No problems sent in this session."),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
