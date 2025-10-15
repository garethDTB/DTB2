// lib/features/problem_detail/presentation/widgets/action_buttons_row.dart
import 'package:flutter/material.dart';

class ActionButtonsRow extends StatefulWidget {
  final bool likedByUser;
  final int likesCount;
  final VoidCallback onToggleLike;
  final VoidCallback onAttempt;
  final VoidCallback onTick;
  final VoidCallback onFlash;
  final VoidCallback onSendToBoard;
  final bool isMirrored;
  final VoidCallback onMirrorToggle;
  final VoidCallback? onWhatsOn;
  final VoidCallback? onComments;

  const ActionButtonsRow({
    super.key,
    required this.likedByUser,
    required this.likesCount,
    required this.onToggleLike,
    required this.onAttempt,
    required this.onTick,
    required this.onFlash,
    required this.onSendToBoard,
    required this.isMirrored,
    required this.onMirrorToggle,
    this.onWhatsOn,
    this.onComments,
  });

  @override
  State<ActionButtonsRow> createState() => _ActionButtonsRowState();
}

class _ActionButtonsRowState extends State<ActionButtonsRow> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicators);
  }

  void _updateScrollIndicators() {
    setState(() {
      _canScrollLeft = _scrollController.offset > 0;
      _canScrollRight =
          _scrollController.offset < _scrollController.position.maxScrollExtent;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Row(
        children: [
          // Left arrow indicator
          if (_canScrollLeft)
            const Icon(Icons.chevron_left, size: 28, color: Colors.grey),

          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // ❤️ Like
                  _buildButton(
                    icon: Icon(
                      Icons.favorite,
                      color: widget.likedByUser ? Colors.purple : Colors.grey,
                      size: widget.likedByUser ? 30 : 26,
                    ),
                    label: "${widget.likesCount}",
                    onPressed: widget.onToggleLike,
                  ),

                  // ❌ Attempt
                  _buildButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 28),
                    label: "Attempt",
                    onPressed: widget.onAttempt,
                  ),

                  // ✅ Tick
                  _buildButton(
                    icon: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 28,
                    ),
                    label: "Tick",
                    onPressed: widget.onTick,
                  ),

                  // ⚡ Flash
                  _buildButton(
                    icon: const Icon(
                      Icons.bolt,
                      color: Colors.orange,
                      size: 28,
                    ),
                    label: "Flash",
                    onPressed: widget.onFlash,
                  ),

                  // 💡 Send (bulb)
                  _buildButton(
                    icon: const Icon(
                      Icons.lightbulb,
                      color: Colors.blue,
                      size: 28,
                    ),
                    label: "Send",
                    onPressed: widget.onSendToBoard,
                  ),

                  // 🔄 Mirror toggle
                  _buildButton(
                    icon: Icon(
                      Icons.flip,
                      color: widget.isMirrored ? Colors.teal : Colors.grey,
                      size: 28,
                    ),
                    label: "Mirror",
                    onPressed: widget.onMirrorToggle,
                  ),

                  // 📺 What's On
                  if (widget.onWhatsOn != null)
                    _buildButton(
                      icon: const Icon(
                        Icons.tv,
                        color: Colors.indigo,
                        size: 28,
                      ),
                      label: "What's On",
                      onPressed: widget.onWhatsOn!,
                    ),

                  // 💬 Comments
                  if (widget.onComments != null)
                    _buildButton(
                      icon: const Icon(
                        Icons.comment,
                        color: Colors.brown,
                        size: 28,
                      ),
                      label: "Comments",
                      onPressed: widget.onComments!,
                    ),
                ],
              ),
            ),
          ),

          // Right arrow indicator
          if (_canScrollRight)
            const Icon(Icons.chevron_right, size: 28, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildButton({
    required Icon icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: icon, onPressed: onPressed),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
