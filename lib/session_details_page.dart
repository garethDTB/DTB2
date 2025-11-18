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

class _SessionDetailsPageState extends State<SessionDetailsPage> {
  late Session _session;
  String gradeMode = "french"; // default

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

  // --------------------------
  // DELETE by INDEX (not name)
  // --------------------------
  Future<void> _deleteProblem(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Problem"),
        content: const Text(
          "Are you sure you want to permanently delete this problem from your logbook? This cannot be undone.",
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

      // IMPORTANT: send index instead of problem name
      final updatedJson = await api.deleteSentProblem(
        _session.wall,
        _session.id,
        index, // ⭐ delete specific item
        auth.username ?? "guest",
      );

      setState(() {
        _session = Session.fromJson(updatedJson);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Problem deleted successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
    }
  }

  String _displayProblemName(SentProblem problem) {
    final rawName = problem.problem;
    final grade = problem.grade;

    if (gradeMode == "vgrade") {
      return rawName.replaceAll(grade, frenchToVGrade(grade));
    }
    return rawName;
  }

  @override
  Widget build(BuildContext context) {
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
          "${_session.wall} — "
          "${DateFormat.yMMMd().format(_session.date)}",
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Summary Card
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.info, color: Colors.blue),
                title: Text(
                  "Score: ${_session.score}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text("Problems sent: $totalSent"),
              ),
            ),

            // Attempts Section
            if (attempts.isNotEmpty)
              ExpansionTile(
                title: const Text(
                  "Attempts",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                children: attempts.map((a) {
                  return ListTile(
                    title: Text(a.problem),
                    trailing: Text("${a.attempts} tries"),
                  );
                }).toList(),
              ),

            // Sent Problems Section
            ExpansionTile(
              initiallyExpanded: true,
              title: const Text(
                "Sent Problems",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              children: sent.isNotEmpty
                  ? List.generate(sent.length, (index) {
                      final s = sent[index];

                      return ListTile(
                        title: Text(_displayProblemName(s)),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                gradeMode == "vgrade"
                                    ? frenchToVGrade(s.grade)
                                    : s.grade,
                              ),
                              backgroundColor: Colors.blue[100],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteProblem(index),
                            ),
                          ],
                        ),
                      );
                    })
                  : [
                      const ListTile(
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
