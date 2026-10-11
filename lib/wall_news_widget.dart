import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';

import 'services/wall_news_service.dart';

class WallNewsWidget extends StatefulWidget {
  final List<String> wallIds;

  final String username;

  final ApiService api;

  final String currentWallId;

  final Future<void> Function(
    String title,

    String wallId,

    List<String> problemNames,
  )
  onViewAll;

  final Future<void> Function(String wallId, String problemName) onOpenProblem;

  final ValueChanged<bool>? onExpansionChanged;

  const WallNewsWidget({
    super.key,

    required this.wallIds,

    required this.username,

    required this.api,

    required this.currentWallId,

    required this.onViewAll,

    required this.onOpenProblem,
    this.onExpansionChanged,
  });

  @override
  State<WallNewsWidget> createState() => _WallNewsWidgetState();
}

class _WallNewsWidgetState extends State<WallNewsWidget> {
  bool expanded = false, loading = false;

  int tab = 0;

  String? error;

  Map<String, dynamic>? data;

  DateTime? previousVisit;

  String get centreKey {
    final ids = [...widget.wallIds]..sort();

    return 'wall_news_seen_${widget.username}_${ids.join('|')}';
  }

  @override
  void didUpdateWidget(covariant WallNewsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.username != widget.username ||
        oldWidget.wallIds.join('|') != widget.wallIds.join('|')) {
      expanded = false;

      data = null;

      error = null;

      previousVisit = null;
    }
  }

  Future<void> open() async {
    if (expanded) {
      setState(() => expanded = false);
      widget.onExpansionChanged?.call(false);

      return;
    }

    setState(() {
      expanded = true;

      loading = true;

      error = null;
    });

    widget.onExpansionChanged?.call(true);

    final prefs = await SharedPreferences.getInstance();

    final prior = DateTime.tryParse(prefs.getString(centreKey) ?? '');

    final service = WallNewsService(widget.api);

    try {
      final cached = await service.cached(widget.wallIds);

      if (mounted && cached != null)
        setState(() {
          data = cached;

          previousVisit = prior;

          loading = false;
        });

      final fresh = await service.load(widget.wallIds);

      if (!mounted || !expanded) return;

      setState(() {
        data = fresh;

        previousVisit = prior;

        loading = false;
      });

      // Save the opening time, not the time the network request completed.

      await prefs.setString(
        centreKey,

        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';

          loading = false;
        });
    }
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;

      error = null;
    });

    try {
      final fresh = await WallNewsService(
        widget.api,
      ).load(widget.wallIds, force: true);

      if (mounted)
        setState(() {
          data = fresh;

          loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';

          loading = false;
        });
    }
  }

  List<Map<String, dynamic>> get routes => (data?['routes'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<Map<String, dynamic>> get events => (data?['events'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  DateTime? date(dynamic value) => DateTime.tryParse('$value');

  bool recent(dynamic value, {int days = 7}) {
    final d = date(value);

    return d != null &&
        d.isAfter(DateTime.now().toUtc().subtract(Duration(days: days)));
  }

  bool sinceVisit(dynamic value) {
    final d = date(value);

    return d != null &&
        d.isAfter(
          previousVisit ??
              DateTime.now().toUtc().subtract(const Duration(days: 7)),
        );
  }

  String age(dynamic value) {
    final d = date(value);

    if (d == null) return 'Unknown date';

    final days = DateTime.now().toUtc().difference(d.toUtc()).inDays;

    return days <= 0
        ? 'Today'
        : days == 1
        ? 'Yesterday'
        : '$days days ago';
  }

  Widget line(
    IconData icon,

    String title,

    String subtitle, {

    String? wallId,

    String? problemName,
  }) {
    final Color accent = icon == Icons.fiber_new
        ? Colors.green
        : icon == Icons.local_fire_department_outlined
        ? Colors.orange
        : icon == Icons.emoji_events_outlined
        ? Colors.purple
        : icon == Icons.bolt
        ? Colors.amber
        : Colors.blue;
    return ListTile(
      dense: true,

      contentPadding: EdgeInsets.zero,

      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 22, color: accent),
      ),

      title: Text(title),

      subtitle: Text(subtitle),

      trailing: wallId != null && problemName != null
          ? const Icon(Icons.chevron_right)
          : null,

      onTap: wallId != null && problemName != null
          ? () => widget.onOpenProblem(wallId, problemName)
          : null,
    );
  }

  Future<void> _viewAll(String title, List<Map<String, dynamic>> items) async {
    final byWall = <String, Set<String>>{};

    for (final item in items) {
      final wall = (item['wall'] ?? '').toString().trim();

      final name = (item['problem'] ?? '').toString().trim();

      if (wall.isNotEmpty && name.isNotEmpty) {
        byWall.putIfAbsent(wall, () => <String>{}).add(name);
      }
    }

    if (byWall.isEmpty) return;

    String? selectedWall;

    if (byWall.length == 1) {
      selectedWall = byWall.keys.first;
    } else {
      selectedWall = await showDialog<String>(
        context: context,

        builder: (dialogContext) => AlertDialog(
          title: Text(title),

          content: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              const Text('Choose which wall to view'),

              const SizedBox(height: 8),

              ...byWall.entries.map(
                (entry) => ListTile(
                  title: Text(
                    entry.key == widget.currentWallId
                        ? 'Stay on ${entry.key}'
                        : 'Change to ${entry.key}',
                  ),

                  subtitle: Text('${entry.value.length} problems'),

                  onTap: () => Navigator.pop(dialogContext, entry.key),
                ),
              ),
            ],
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),

              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }

    if (selectedWall == null || !mounted) return;

    await widget.onViewAll(title, selectedWall, byWall[selectedWall]!.toList());
  }

  // A section can show a short preview and open its complete, deduplicated list.

  Widget section(
    String title,

    List<Widget> children, {

    List<Map<String, dynamic>>? allProblems,
  }) {
    final unique = <String, Map<String, dynamic>>{};

    for (final item in allProblems ?? <Map<String, dynamic>>[]) {
      final wall = (item['wall'] ?? '').toString().trim();

      final problem = (item['problem'] ?? '').toString().trim();

      if (wall.isNotEmpty && problem.isNotEmpty) {
        unique.putIfAbsent('$wall|$problem', () => item);
      }
    }

    final items = unique.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),

          child: Text(
            title,

            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),

            child: Text('No activity to show yet.'),
          ),

        ...children,

        if (items.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,

            child: TextButton.icon(
              onPressed: () => _viewAll(title, items),

              icon: const Icon(Icons.arrow_forward, size: 18),

              label: Text('View all ${items.length} problems'),
            ),
          ),
      ],
    );
  }

  Widget forYou() {
    final since = events.where((e) => sinceVisit(e['date'])).toList();

    final newRoutes = routes
        .where((p) => sinceVisit(p['estimatedDate']))
        .toList();

    final mine = events
        .where((e) => recent(e['date'], days: 30))
        .where(
          (e) =>
              '${e['setter']}'.toLowerCase() == widget.username.toLowerCase(),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        Text(
          previousVisit == null
              ? 'Activity from the last 7 days'
              : 'Since your previous news visit',
        ),

        Wrap(
          spacing: 8,

          runSpacing: 8,

          children: [
            Chip(label: Text('${newRoutes.length} estimated new problems')),

            Chip(label: Text('${since.length} ascents')),

            Chip(label: Text('${mine.length} ascents of your problems')),
          ],
        ),

        section(
          'Who climbed your problems',

          allProblems: mine,

          mine
              .take(15)
              .map(
                (e) => line(
                  Icons.people_outline,

                  '${e['user']} climbed ${e['problem']}',

                  '${e['wall']} · ${age(e['date'])}',

                  wallId: '${e['wall']}',

                  problemName: '${e['problem']}',
                ),
              )
              .toList(),
        ),

        section(
          'Recent ascents',

          allProblems: since,

          since
              .take(15)
              .map(
                (e) => line(
                  e['flash'] == true ? Icons.bolt : Icons.check_circle_outline,

                  '${e['user']} ${e['flash'] == true ? 'flashed' : 'climbed'} ${e['problem']}',

                  '${e['wall']} · ${age(e['date'])}',

                  wallId: '${e['wall']}',

                  problemName: '${e['problem']}',
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget centre() {
    final ascents = events.where((e) => recent(e['date'])).take(30).toList();

    final firsts = routes
        .where(
          (r) =>
              r['firstAscent'] != null &&
              recent((r['firstAscent'] as Map)['date']),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        section(
          'Latest ascents',

          allProblems: events.where((e) => recent(e['date'])).toList(),

          ascents
              .map(
                (e) => line(
                  e['flash'] == true ? Icons.bolt : Icons.check,

                  '${e['user']} ${e['flash'] == true ? 'flashed' : 'climbed'} ${e['problem']}',

                  '${e['wall']} · ${age(e['date'])}',

                  wallId: '${e['wall']}',

                  problemName: '${e['problem']}',
                ),
              )
              .toList(),
        ),

        section(
          'First recorded ascents',

          allProblems: firsts,

          firsts
              .take(12)
              .map(
                (r) => line(
                  Icons.emoji_events_outlined,

                  '${(r['firstAscent'] as Map)['user']} · ${r['problem']}',

                  '${r['wall']} · ${age((r['firstAscent'] as Map)['date'])}',

                  wallId: '${r['wall']}',

                  problemName: '${r['problem']}',
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget discover() {
    final fresh = routes.where((p) => recent(p['estimatedDate'])).toList()
      ..sort(
        (a, b) => '${b['estimatedDate']}'.compareTo('${a['estimatedDate']}'),
      );

    final recentCounts = <String, int>{};

    for (final e in events.where((e) => recent(e['date']))) {
      final key = '${e['wall']}|${e['problem']}';

      recentCounts[key] = (recentCounts[key] ?? 0) + 1;
    }

    final trending =
        routes
            .where(
              (r) => recentCounts.containsKey('${r['wall']}|${r['problem']}'),
            )
            .toList()
          ..sort(
            (a, b) => (recentCounts['${b['wall']}|${b['problem']}'] ?? 0)
                .compareTo(recentCounts['${a['wall']}|${a['problem']}'] ?? 0),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        section(
          'Recently added problems',

          allProblems: fresh,

          fresh
              .take(20)
              .map(
                (r) => line(
                  Icons.fiber_new,

                  '${r['problem']}',

                  '${r['wall']} · ${age(r['estimatedDate'])}',

                  wallId: '${r['wall']}',

                  problemName: '${r['problem']}',
                ),
              )
              .toList(),
        ),

        section(
          'Trending this week',

          allProblems: trending,

          trending
              .take(15)
              .map(
                (r) => line(
                  Icons.local_fire_department_outlined,

                  '${r['problem']}',

                  '${r['wall']} · ${recentCounts['${r['wall']}|${r['problem']}']} ascents',

                  wallId: '${r['wall']}',

                  problemName: '${r['problem']}',
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,

    children: [
      ElevatedButton(
        onPressed: open,

        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),

          textStyle: const TextStyle(fontSize: 18),
        ),

        child: Stack(
          alignment: Alignment.center,

          children: [
            const Text('Wall News'),

            Positioned(
              right: 14,

              child: Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              ),
            ),
          ],
        ),
      ),

      if (expanded) ...[
        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.all(12),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.wallIds.length} board(s) at this location',

                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),

                  IconButton(
                    onPressed: loading ? null : refresh,

                    icon: const Icon(Icons.refresh),

                    tooltip: 'Refresh news',
                  ),
                ],
              ),

              SegmentedButton<int>(
                showSelectedIcon: false,

                segments: const [
                  ButtonSegment(value: 0, label: Text('For You')),

                  ButtonSegment(value: 1, label: Text('Centre')),

                  ButtonSegment(value: 2, label: Text('Discover')),
                ],

                selected: {tab},

                onSelectionChanged: (value) =>
                    setState(() => tab = value.first),
              ),

              if (loading) const LinearProgressIndicator(),

              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(8),

                  child: Text('News refresh failed: $error'),
                ),

              if (data != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),

                  child: tab == 0
                      ? forYou()
                      : tab == 1
                      ? centre()
                      : discover(),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}
