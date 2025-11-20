// lib/features/comments/presentation/comments_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../services/api_service.dart';
import '../../../../../../hold_utils.dart'; // contains frenchToVGrade / vToFrench / gradePoints

class CommentsPage extends StatefulWidget {
  final String wallId;
  final String problemName;
  final String user;
  final String grade; // ★ Official grade (always French)

  const CommentsPage({
    super.key,
    required this.wallId,
    required this.problemName,
    required this.user,
    required this.grade,
  });

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  bool _loading = true;

  List<Map<String, dynamic>> _comments = [];
  final TextEditingController _controller = TextEditingController();

  String gradeMode = "french"; // loaded from SharedPreferences
  String? _selectedSuggestedGrade; // stored internally as FRENCH

  // French grade list for dropdown
  final List<String> _frenchGrades = [
    "4a",
    "4b",
    "4c",
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
  ];

  @override
  void initState() {
    super.initState();
    _loadGradeMode();
  }

  Future<void> _loadGradeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      gradeMode = prefs.getString("gradeMode") ?? "french";
    });

    _loadComments();
  }

  Future<void> _loadComments() async {
    final api = context.read<ApiService>();

    try {
      final data = await api.getComments(widget.wallId, widget.problemName);
      final loaded = List<Map<String, dynamic>>.from(data ?? []);

      // Sort newest → oldest
      loaded.sort((a, b) {
        final da = DateTime.tryParse(a["Date"] ?? "") ?? DateTime(0);
        final db = DateTime.tryParse(b["Date"] ?? "") ?? DateTime(0);
        return db.compareTo(da);
      });

      // Prefill user comment + user grade
      final existing = loaded.firstWhere(
        (c) => c["User"] == widget.user,
        orElse: () => {},
      );

      if (existing.isNotEmpty) {
        _controller.text = existing["Comment"] ?? "";

        final g = existing["Suggested_grade"]?.toString() ?? "";
        if (g.isNotEmpty) _selectedSuggestedGrade = g;
      }

      setState(() {
        _comments = loaded;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load comments: $e")));
    }
  }

  // Convert French grade → display (French or V)
  String _displayGrade(String french) {
    return gradeMode == "vgrade" ? frenchToVGrade(french) : french;
  }

  // Convert UI selection → French (for Azure upload)
  String _convertToFrench(String displayed) {
    return gradeMode == "vgrade" ? vToFrench(displayed) : displayed;
  }

  Future<void> _saveComment() async {
    final text = _controller.text.trim();
    final api = context.read<ApiService>();

    final frenchGrade = _selectedSuggestedGrade == null
        ? ""
        : _convertToFrench(_selectedSuggestedGrade!);

    try {
      await api.saveComment(
        widget.wallId,
        widget.problemName,
        widget.user,
        frenchGrade,
        text,
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Saved")));

      _loadComments();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    }
  }

  int _pts(String g) => gradePoints[g.toLowerCase()] ?? 0;

  // ★ Compute average suggested grade
  String? _averageSuggestedGrade() {
    final all = _comments
        .map((c) => c["Suggested_grade"]?.toString() ?? "")
        .where((g) => g.isNotEmpty)
        .toList();

    if (all.isEmpty) return null;

    final pts = all.map(_pts).toList();
    final avg = pts.reduce((a, b) => a + b) / pts.length;

    String best = "6a";
    double bestDiff = double.infinity;

    gradePoints.forEach((grade, value) {
      final diff = (value - avg).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = grade;
      }
    });

    return gradeMode == "vgrade" ? frenchToVGrade(best) : best;
  }

  // ★ Difficulty indicator widget
  Widget _difficultyIndicator(String suggestedFrench) {
    final official = widget.grade.toLowerCase();
    final sug = suggestedFrench.toLowerCase();

    final offPts = _pts(official);
    final sugPts = _pts(sug);

    if (sugPts > offPts) {
      return Text(
        "↑ harder",
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      );
    } else if (sugPts < offPts) {
      return Text(
        "↓ easier",
        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
      );
    } else {
      return Text(
        "≈ same",
        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userOwn = _comments.firstWhere(
      (c) => c["User"] == widget.user,
      orElse: () => {},
    );

    final others = _comments.where((c) => c["User"] != widget.user).toList();

    final avg = _averageSuggestedGrade();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: Text("Comments – ${widget.problemName}")),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // =========================================
                  // ★ AVERAGE SUGGESTED GRADE
                  // =========================================
                  if (avg != null)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        "Average suggested grade: $avg",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  // =========================================
                  // ★ USER COMMENT FIRST
                  // =========================================
                  if (userOwn.isNotEmpty &&
                      (userOwn["Comment"] ?? "").toString().isNotEmpty)
                    Card(
                      color: Colors.yellow.shade100,
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text(
                          userOwn["User"],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((userOwn["Suggested_grade"] ?? "")
                                .toString()
                                .isNotEmpty)
                              Row(
                                children: [
                                  Text(
                                    "Suggested: ${_displayGrade(userOwn["Suggested_grade"])}  ",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  _difficultyIndicator(
                                    userOwn["Suggested_grade"],
                                  ),
                                ],
                              ),
                            Text(userOwn["Comment"]),
                          ],
                        ),
                      ),
                    ),

                  // =========================================
                  // ★ OTHER COMMENTS
                  // =========================================
                  Expanded(
                    child: others.isEmpty
                        ? const Center(child: Text("No comments yet"))
                        : ListView.builder(
                            itemCount: others.length,
                            itemBuilder: (context, i) {
                              final c = others[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  title: Text(
                                    c["User"],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if ((c["Suggested_grade"] ?? "")
                                          .toString()
                                          .isNotEmpty)
                                        Row(
                                          children: [
                                            Text(
                                              "Suggested: ${_displayGrade(c["Suggested_grade"])}  ",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            _difficultyIndicator(
                                              c["Suggested_grade"],
                                            ),
                                          ],
                                        ),
                                      Text(c["Comment"]),
                                    ],
                                  ),
                                  trailing: Text(c["Date"] ?? ""),
                                ),
                              );
                            },
                          ),
                  ),

                  // =========================================
                  // ★ INPUT FIELD + GRADE DROPDOWN + SAVE BUTTON
                  // =========================================
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text("Suggested grade: "),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                hint: const Text("None"),
                                value: _selectedSuggestedGrade,
                                items: _frenchGrades.map((fr) {
                                  return DropdownMenuItem(
                                    value: fr,
                                    child: Text(_displayGrade(fr)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() => _selectedSuggestedGrade = val);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  decoration: const InputDecoration(
                                    labelText: "Your comment",
                                    border: OutlineInputBorder(),
                                  ),
                                  minLines: 1,
                                  maxLines: 3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _saveComment,
                                icon: const Icon(Icons.send),
                                label: const Text("Save"),
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
}
