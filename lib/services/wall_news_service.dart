import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class WallNewsService {
  final ApiService api;
  WallNewsService(this.api);

  static const cacheLifetime = Duration(hours: 24);

  Future<File> _file(List<String> wallIds) async {
    final dir = await getApplicationDocumentsDirectory();
    final ids = [...wallIds]..sort();
    final key = base64Url
        .encode(utf8.encode(ids.join('|')))
        .replaceAll('=', '');
    final folder = Directory('${dir.path}/wall_news');
    await folder.create(recursive: true);
    return File('${folder.path}/$key.json');
  }

  Future<Map<String, dynamic>?> cached(List<String> wallIds) async {
    try {
      final file = await _file(wallIds);
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      return Map<String, dynamic>.from(value as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> load(
    List<String> wallIds, {
    bool force = false,
  }) async {
    final old = await cached(wallIds);
    final saved = DateTime.tryParse('${old?['fetchedAt'] ?? ''}');
    if (!force &&
        old != null &&
        saved != null &&
        DateTime.now().toUtc().difference(saved.toUtc()) < cacheLifetime)
      return old;
    final ids = wallIds.toSet().toList()..sort();
    final results = await Future.wait(
      ids.map((id) async {
        final problems = await api.getWallProblems(id);
        final sessions = await api.getAllSessionsForWall(id);
        return {'wall': id, 'problems': problems, 'sessions': sessions};
      }),
    );
    final processed = _process(results);
    processed['fetchedAt'] = DateTime.now().toUtc().toIso8601String();
    await (await _file(ids)).writeAsString(jsonEncode(processed), flush: true);
    return processed;
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is num)
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      );
    return DateTime.tryParse('$value')?.toUtc();
  }

  static String _key(String wall, String name) => jsonEncode([wall, name]);

  Map<String, dynamic> _process(List<Map<String, dynamic>> boards) {
    final routes = <String, Map<String, dynamic>>{};
    final events = <Map<String, dynamic>>[];
    final firstActivity = <String, DateTime>{};
    final firstSend = <String, Map<String, dynamic>>{};
    for (final board in boards) {
      final wall = '${board['wall']}';
      for (final raw in (board['problems'] as List)) {
        final p = Map<String, dynamic>.from(raw as Map);
        final name = '${p['Problem'] ?? ''}';
        if (name.isEmpty) continue;
        routes[_key(wall, name)] = {
          'wall': wall,
          'problem': name,
          'grade': '${p['Grade'] ?? ''}',
          'setter': '${p['Setter'] ?? ''}',
          'created': p['Created'],
          'modified': p['_ts'],
          'id': p['id'],
          'ascents': 0,
          'flashes': 0,
        };
      }
    }
    for (final board in boards) {
      final wall = '${board['wall']}';
      for (final raw in (board['sessions'] as List)) {
        final session = Map<String, dynamic>.from(raw as Map);
        final date = _date(session['Date']);
        if (date == null) continue;
        final user = '${session['User'] ?? ''}';
        for (final category in ['Attempts', 'Sent']) {
          for (final item in (session[category] as List? ?? [])) {
            if (item is! Map) continue;
            final name = '${item['Problem'] ?? ''}';
            final key = _key(wall, name);
            if (!routes.containsKey(key))
              continue; // ignore deleted/renamed problems
            final earlier = firstActivity[key];
            if (earlier == null || date.isBefore(earlier))
              firstActivity[key] = date;
            if (category != 'Sent') continue;
            final flash = item['Flash'] == true;
            final event = <String, dynamic>{
              'wall': wall,
              'problem': name,
              'user': user,
              'grade': routes[key]!['grade'],
              'setter': routes[key]!['setter'],
              'date': date.toIso8601String(),
              'flash': flash,
            };
            events.add(event);
            routes[key]!['ascents'] = (routes[key]!['ascents'] as int) + 1;
            if (flash)
              routes[key]!['flashes'] = (routes[key]!['flashes'] as int) + 1;
            final prior = firstSend[key];
            if (prior == null || date.isBefore(_date(prior['date'])!))
              firstSend[key] = event;
          }
        }
      }
    }
    for (final entry in routes.entries) {
      final p = entry.value;
      final first = firstActivity[entry.key];
      final created = _date(p['created']);
      final modified = _date(p['modified']);
      // Old bulk uploads: prefer earliest recorded activity. This is an estimate, not a verified set date.
      final estimated = first ?? created ?? modified;
      p['estimatedDate'] = estimated?.toIso8601String();
      p['dateSource'] = first != null
          ? 'first activity'
          : created != null
          ? 'created'
          : 'last modified';
      p['firstAscent'] = firstSend[entry.key];
    }
    events.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return {'routes': routes.values.toList(), 'events': events};
  }
}
