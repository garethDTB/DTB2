// lib/features/comments/presentation/comments_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../services/api_service.dart';
import '../../../../../../auth_state.dart';

class CommentsPage extends StatefulWidget {
  final String wallId;
  final String problemName;
  final String user;

  const CommentsPage({
    super.key,
    required this.wallId,
    required this.problemName,
    required this.user,
  });

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _comments = [];
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  /// Check whether this user already has a comment
  bool get userHasComment {
    return _comments.any((c) => c["User"] == widget.user);
  }

  Map<String, dynamic>? get userComment {
    return _comments.firstWhere(
      (c) => c["User"] == widget.user,
      orElse: () => {},
    );
  }

  Future<void> _loadComments() async {
    final api = context.read<ApiService>();
    try {
      final data = await api.getComments(widget.wallId, widget.problemName);

      List<Map<String, dynamic>> loaded = List<Map<String, dynamic>>.from(
        data ?? [],
      );

      // Sort newest → oldest
      loaded.sort((a, b) {
        final da = DateTime.tryParse(a["Date"] ?? "") ?? DateTime(0);
        final db = DateTime.tryParse(b["Date"] ?? "") ?? DateTime(0);
        return db.compareTo(da);
      });

      setState(() {
        _comments = loaded;
        _loading = false;
      });

      // Prefill user's existing comment
      final existing = userComment;
      if (existing != null && existing.isNotEmpty) {
        _controller.text = existing["Comment"] ?? "";
      }
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load comments: $e")));
    }
  }

  Future<void> _saveComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final api = context.read<ApiService>();

    try {
      await api.saveComment(
        widget.wallId,
        widget.problemName,
        widget.user,
        "", // grade unused
        text,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userHasComment ? "Comment updated" : "Comment saved"),
        ),
      );

      _loadComments();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to save comment: $e")));
    }
  }

  /// DELETE = save a blank comment
  Future<void> _deleteComment() async {
    final api = context.read<ApiService>();

    try {
      await api.saveComment(
        widget.wallId,
        widget.problemName,
        widget.user,
        "", // grade
        "", // blank comment text
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Comment removed")));

      _controller.clear();
      _loadComments();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to remove comment: $e")));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userOwn = userComment;

    // All other comments except user's
    final otherComments = _comments
        .where((c) => c["User"] != widget.user)
        .toList();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: Text("Comments – ${widget.problemName}")),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // =========================================
                  //   USER COMMENT (highlighted at top)
                  // =========================================
                  if (userOwn != null &&
                      userOwn.isNotEmpty &&
                      (userOwn["Comment"] ?? "").toString().isNotEmpty)
                    Card(
                      color: Colors.yellow.shade100,
                      margin: const EdgeInsets.all(8),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.orange, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          userOwn["User"] ?? "You",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(userOwn["Comment"] ?? ""),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: _deleteComment,
                        ),
                      ),
                    ),

                  // =========================================
                  //   OTHER COMMENTS
                  // =========================================
                  Expanded(
                    child: otherComments.isEmpty
                        ? const Center(child: Text("No other comments"))
                        : ListView.builder(
                            itemCount: otherComments.length,
                            itemBuilder: (context, idx) {
                              final c = otherComments[idx];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  title: Text(c["User"] ?? "unknown"),
                                  subtitle: Text(c["Comment"] ?? ""),
                                  trailing: Text(c["Date"] ?? ""),
                                ),
                              );
                            },
                          ),
                  ),

                  // =========================================
                  //   INPUT FIELD & SAVE / EDIT BUTTON
                  // =========================================
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
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
                            label: Text(userHasComment ? "Edit" : "Save"),
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
