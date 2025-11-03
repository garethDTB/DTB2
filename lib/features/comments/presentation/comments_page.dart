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

  Future<void> _loadComments() async {
    final api = context.read<ApiService>();
    try {
      final data = await api.getComments(widget.wallId, widget.problemName);
      setState(() {
        _comments = List<Map<String, dynamic>>.from(data ?? []);
        _loading = false;
      });

      // if user already has a comment, prefill
      final existing = _comments.firstWhere(
        (c) => c["User"] == widget.user,
        orElse: () => {},
      );
      if (existing.isNotEmpty) {
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
      // check if user already commented
      final existing = _comments.firstWhere(
        (c) => c["User"] == widget.user,
        orElse: () => {},
      );
      await api.saveComment(
        widget.wallId,
        widget.problemName,
        widget.user,
        "", // grade if you need it
        text,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Comment saved")));
      _loadComments();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to save comment: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Comments – ${widget.problemName}")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 💬 Comments list
                Expanded(
                  child: _comments.isEmpty
                      ? const Center(child: Text("No comments yet"))
                      : ListView.builder(
                          itemCount: _comments.length,
                          itemBuilder: (context, idx) {
                            final c = _comments[idx];
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

                // 🧷 Input box always visible and safe
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
                          label: const Text("Save"),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
