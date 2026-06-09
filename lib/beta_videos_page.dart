import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';

class BetaVideosPage extends StatefulWidget {
  final String problemId;
  final String problemName;
  final String grade;
  final String wallName;
  final String angle;
  final String setter;

  const BetaVideosPage({
    super.key,
    required this.problemId,
    required this.problemName,
    required this.grade,
    required this.wallName,
    required this.angle,
    required this.setter,
  });

  @override
  State<BetaVideosPage> createState() => _BetaVideosPageState();
}

class _BetaVideosPageState extends State<BetaVideosPage> {
  List<Map<String, dynamic>> betaVideos = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadBetaVideos();
  }

  String _cleanTag(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String get hashtags {
    final cleanProblem = _cleanTag(widget.problemName);
    final cleanWall = _cleanTag(widget.wallName);

    final wallTag = 'dtbwall$cleanWall';
    final climbTag = 'dtb${cleanWall}_$cleanProblem';

    return '''
#dtbbeta
#dtbclimbing
#$wallTag
#$climbTag
''';
  }

  String get caption {
    return '''
${widget.problemName}
Grade: ${widget.grade}
Wall: ${widget.wallName}
${widget.angle.isNotEmpty ? 'Angle: ${widget.angle}\n' : ''}${widget.setter.isNotEmpty ? 'Setter: ${widget.setter}\n' : ''}

Tag: @digitaltrainingboards

$hashtags
''';
  }

  Future<void> _loadBetaVideos() async {
    try {
      final api = context.read<ApiService>();

      final videos = await api.getBetaVideos(widget.wallName, widget.problemId);

      if (!mounted) return;

      setState(() {
        betaVideos = videos;
        loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load beta videos: $e');

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _copyCaption(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: caption));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Caption copied')));
  }

  Future<void> _copyHashtagsOnly(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: hashtags));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Hashtags copied')));
  }

  Future<void> _openInstagram() async {
    final instagramApp = Uri.parse('instagram://camera');
    final instagramWeb = Uri.parse('https://www.instagram.com/');

    if (await canLaunchUrl(instagramApp)) {
      await launchUrl(instagramApp);
    } else {
      await launchUrl(instagramWeb, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyAndOpenInstagram(BuildContext context) async {
    await _copyCaption(context);
    await _openInstagram();
  }

  Future<void> _openExistingBetas() async {
    final cleanProblem = _cleanTag(widget.problemName);
    final cleanWall = _cleanTag(widget.wallName);
    final climbTag = 'dtb${cleanWall}_$cleanProblem';

    final url = Uri.parse('https://www.instagram.com/explore/tags/$climbTag/');

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareVideoPrompt() async {
    await Share.share(
      'Post your beta video for ${widget.problemName} on ${widget.wallName}.\n\n'
      'Please paste this into your Instagram caption and tag @digitaltrainingboards.\n\n'
      '$caption',
    );
  }

  Widget _button({
    required IconData icon,
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(text, style: const TextStyle(fontSize: 16)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildVideoList() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (betaVideos.isEmpty) {
      return const Text(
        'No beta videos linked yet.',
        style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
      );
    }

    return Column(
      children: betaVideos.map((video) {
        final url = (video['Url'] ?? '').toString();
        final username = (video['Username'] ?? 'Instagram').toString();
        final captionText = (video['Caption'] ?? '').toString();

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              if (url.isNotEmpty) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((video['ThumbnailUrl'] ?? '').toString().isNotEmpty)
                  Image.network(
                    video['ThumbnailUrl'],
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 220),
                  ),

                ListTile(
                  leading: const Icon(Icons.play_circle),
                  title: Text(username),
                  subtitle: Text(
                    captionText.isNotEmpty ? captionText : url,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.open_in_new),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beta Videos')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            const Text(
              'Post a beta video to Instagram using the generated caption. '
              'For best results, paste the caption into the post caption, tag @digitaltrainingboards, '
              'and make sure your account is public. The climb-specific hashtag makes it possible '
              'to find videos for this problem.',
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              color: Colors.white,
              child: Text(caption, style: const TextStyle(fontSize: 16)),
            ),

            const SizedBox(height: 22),

            _button(
              icon: Icons.content_copy,
              text: 'Copy Caption and Open Instagram',
              onPressed: () => _copyAndOpenInstagram(context),
            ),

            const SizedBox(height: 12),

            _button(
              icon: Icons.tag,
              text: 'Copy Hashtags Only',
              onPressed: () => _copyHashtagsOnly(context),
            ),

            const SizedBox(height: 12),

            _button(
              icon: Icons.video_library,
              text: 'Open Existing Betas',
              onPressed: _openExistingBetas,
            ),

            const SizedBox(height: 12),

            _button(
              icon: Icons.share,
              text: 'Share Video',
              onPressed: _shareVideoPrompt,
            ),

            const SizedBox(height: 32),

            _buildVideoList(),
          ],
        ),
      ),
    );
  }
}
