import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart'; // gives access to routeObserver
import 'logbook_and_leaderboard_page.dart';
import 'auth_state.dart';
import 'login_page.dart';
import 'load_problems_page.dart';
import 'create_problem_page.dart';
import 'settings_page.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'log_book_page.dart';
import 'models/session.dart';
import 'mirror_utils.dart';

// ✅ Dropbox services
import 'services/dropbox_auth_service.dart';
import 'services/dropbox_file_service.dart';

class WallLogPage extends StatefulWidget {
  const WallLogPage({super.key});

  @override
  State<WallLogPage> createState() => _WallLogPageState();
}

class _WallLogPageState extends State<WallLogPage>
    with RouteAware, WidgetsBindingObserver {
  List<Map<String, String>> walls = [];
  String? selectedWall;
  String? lastWall;
  String? _highlightWall; // nearest wall highlight
  Position? _userPosition;
  bool _locationDenied = false;
  Map<String, List<String>> _wallSuperusers = {};

  List<Session> _sessions = [];
  bool _loadingSessions = false;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  SharedPreferences? _prefs;

  // ✅ Dropbox services
  final dropboxAuth = DropboxAuthService();
  late final DropboxFileService dropboxFileService;

  // ✅ Wall loading overlay
  bool _isLoadingWall = false;
  String _loadingMessage = "";

  // ✅ Drafts
  bool _hasWallDrafts = false;

  // ---------------- HELPERS ----------------

  Map<String, String>? _findWall(String wallId) {
    try {
      return walls.firstWhere((w) => w['appName'] == wallId);
    } catch (_) {
      return null;
    }
  }

  Widget _menuButton({required String label, required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 18),
      ),
      child: Text(label),
    );
  }

  Widget _nearestWallBanner() {
    final w = _findWall(_highlightWall!);
    final name = (w?['userName'] ?? _highlightWall!) + " (nearest)";
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.place),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: TextButton(
          onPressed: () => _enterWall(_highlightWall!),
          child: const Text("Select"),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_userPosition == null && selectedWall == null) {
      return const SizedBox.shrink();
    }
    LatLng initialCenter;
    if (selectedWall != null) {
      final wallData = _findWall(selectedWall!);
      final lat = double.tryParse(wallData?['lat'] ?? '');
      final lon = double.tryParse(wallData?['lon'] ?? '');
      if (lat != null && lon != null) {
        initialCenter = LatLng(lat, lon);
      } else {
        initialCenter = LatLng(
          _userPosition?.latitude ?? 0,
          _userPosition?.longitude ?? 0,
        );
      }
    } else {
      initialCenter = LatLng(_userPosition!.latitude, _userPosition!.longitude);
    }
    final markers = <Marker>[
      if (_userPosition != null)
        Marker(
          point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
          width: 40,
          height: 40,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 32),
        ),
      ...walls.map((w) {
        final lat = double.tryParse(w['lat'] ?? '');
        final lon = double.tryParse(w['lon'] ?? '');
        if (lat == null || lon == null) return null;
        final isSelected = w['appName'] == selectedWall;
        return Marker(
          point: LatLng(lat, lon),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _enterWall(w['appName']!),
            child: Icon(
              Icons.location_pin,
              color: isSelected ? Colors.red : Colors.green,
              size: isSelected ? 40 : 30,
            ),
          ),
        );
      }).whereType<Marker>(),
    ];
    return SizedBox(
      height: MediaQuery.of(context).size.height / 3,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: initialCenter, initialZoom: 13),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: 'com.example.dtb2',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }

  Future<File> _getLocalWallFile(String wallId, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final wallDir = Directory('${dir.path}/walls/$wallId');
    if (!await wallDir.exists()) {
      await wallDir.create(recursive: true);
    }
    return File('${wallDir.path}/$filename');
  }

  Future<bool> _hasDrafts(String wallId) async {
    final dir = await getApplicationDocumentsDirectory();
    final draftFile = File("${dir.path}/${wallId}_drafts.csv");

    if (!await draftFile.exists()) return false;

    final lines = await draftFile.readAsLines();

    // Remove empty lines
    final usable = lines.where((l) => l.trim().isNotEmpty).toList();

    // 🟦 NEW RULE:
    // If there's at least 1 usable line, we have a draft.
    return usable.isNotEmpty;
  }

  List<DropdownMenuItem<String>> _buildWallDropdownItems() {
    List<DropdownMenuItem<String>> items = [];

    for (int i = 0; i < walls.length; i++) {
      final w = walls[i];
      final appName = w['appName'] ?? '';
      final userName = w['userName'] ?? '';
      final isNearest = (i == 0); // nearest wall moved to index 0
      final distMeters = double.tryParse(w['computedDistance'] ?? '') ?? -1;

      final distKm = distMeters > 0
          ? (distMeters / 1000).toStringAsFixed(1) + " km"
          : "";

      // --------------------------------------------------------------
      // 1️⃣ SECTION HEADER AT TOP ("Nearest Wall")
      // --------------------------------------------------------------
      if (i == 0) {
        items.add(
          const DropdownMenuItem<String>(
            enabled: false,
            value: null,
            child: Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                "Nearest Wall",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      }

      // --------------------------------------------------------------
      // 2️⃣ DIVIDER AFTER THE NEAREST WALL
      // --------------------------------------------------------------
      if (i == 1) {
        items.add(
          const DropdownMenuItem<String>(
            enabled: false,
            value: null,
            child: Divider(thickness: 1, height: 1),
          ),
        );
      }

      // --------------------------------------------------------------
      // 3️⃣ ACTUAL WALL ENTRY
      // --------------------------------------------------------------
      items.add(
        DropdownMenuItem<String>(
          value: appName,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                userName,
                style: TextStyle(
                  fontWeight: isNearest ? FontWeight.bold : FontWeight.normal,
                  color: isNearest ? Colors.blue : null,
                ),
              ),
              Text(
                distKm,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return items;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPopNext() async {
    // Called when returning to this page from CreateProblemPage
    if (selectedWall != null) {
      final hasDrafts = await _hasDrafts(selectedWall!);

      if (mounted) {
        setState(() {
          _hasWallDrafts = hasDrafts;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dropboxFileService = DropboxFileService(dropboxAuth);

    () async {
      try {
        await _initPrefs();
        await _getUserLocation();
        await _loadWalls();
        await _loadLastWall();
      } catch (e) {
        debugPrint("⚠️ initState error: $e");
      }
    }();
  }

  Future<void> _initPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint("⚠️ SharedPreferences init failed: $e");
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && selectedWall != null) {
      _refreshDraftsStatus();
    }
  }

  Future<void> _refreshDraftsStatus() async {
    if (selectedWall == null) return;
    final hasDrafts = await _hasDrafts(selectedWall!);

    if (mounted) {
      setState(() {
        _hasWallDrafts = hasDrafts;
      });
    }
  }

  /// ✅ Load walllist.csv from Dropbox (fallback to cache/assets)
  Future<void> _loadWalls() async {
    String raw = "";

    // ----------------------------------------------------------------------------
    // 1. LOAD THE RAW CSV (Dropbox → cache → asset)
    // ----------------------------------------------------------------------------
    try {
      final file = await dropboxFileService.downloadAndCacheFile(
        "global",
        "/walllist.csv",
        "walllist.csv",
      );
      raw = await file.readAsString();
      debugPrint("✅ Loaded walllist.csv from Dropbox");
    } catch (e) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final cacheFile = File("${dir.path}/walls/global/walllist.csv");
        if (await cacheFile.exists()) {
          raw = await cacheFile.readAsString();
          debugPrint("⚠️ Dropbox failed, using cached walllist.csv");
        } else {
          raw = await rootBundle.loadString('assets/walllist.csv');
          debugPrint("⚠️ Using asset walllist.csv");
        }
      } catch (_) {
        raw = await rootBundle.loadString('assets/walllist.csv');
        debugPrint("⚠️ Total fallback: asset walllist.csv");
      }
    }

    if (raw.isEmpty) return;
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty) return;

    // ----------------------------------------------------------------------------
    // 2. PARSE CSV INTO MAPS
    // ----------------------------------------------------------------------------
    final data = lines.map((line) {
      final values = line.split(',');
      return {
        'appName': values.length > 6 ? values[6].trim() : "",
        'userName': [
          if (values.length > 2) values[2].trim(),
          if (values.length > 3) values[3].trim(),
        ].join(" ").trim(),
        'lat': values.length > 4 ? values[4].trim() : "",
        'lon': values.length > 5 ? values[5].trim() : "",
      };
    }).toList();

    // ----------------------------------------------------------------------------
    // 3. COMPUTE DISTANCE FOR EVERY WALL  (STEP 1)
    // ----------------------------------------------------------------------------
    if (_userPosition != null) {
      for (final w in data) {
        final lat = double.tryParse(w['lat'] ?? '');
        final lon = double.tryParse(w['lon'] ?? '');

        if (lat != null && lon != null) {
          final dist = Geolocator.distanceBetween(
            _userPosition!.latitude,
            _userPosition!.longitude,
            lat,
            lon,
          );
          w['computedDistance'] = dist.toString();
        } else {
          w['computedDistance'] = '9999999';
        }
      }
    }

    // ----------------------------------------------------------------------------
    // 4. FIND THE NEAREST WALL
    // ----------------------------------------------------------------------------
    if (_userPosition != null) {
      double minDistance = double.infinity;
      String? nearestWall;

      for (final w in data) {
        final dist = double.tryParse(w['computedDistance'] ?? '9999999')!;
        if (dist < minDistance) {
          minDistance = dist;
          nearestWall = w['appName'];
        }
      }

      _highlightWall = nearestWall; // <-- highlight only, do NOT auto-select
    }

    // ----------------------------------------------------------------------------
    // 5. SORT WALLS ALPHABETICALLY (EXCEPT THE NEAREST ONE)
    // ----------------------------------------------------------------------------
    data.sort((a, b) => (a['userName'] ?? '').compareTo(b['userName'] ?? ''));

    // ----------------------------------------------------------------------------
    // 6. MOVE NEAREST WALL TO TOP
    // ----------------------------------------------------------------------------
    if (_highlightWall != null) {
      final nearest = data.firstWhere(
        (w) => w['appName'] == _highlightWall,
        orElse: () => {},
      );

      data.removeWhere((w) => w['appName'] == _highlightWall);
      data.insert(0, nearest);
    }

    // ----------------------------------------------------------------------------
    // 7. SET STATE → update dropdown list
    // ----------------------------------------------------------------------------
    setState(() {
      walls = data;
    });

    // ----------------------------------------------------------------------------
    // 8. CACHE
    // ----------------------------------------------------------------------------
    try {
      await _prefs?.setStringList(
        'walls_cache',
        data.map((w) => jsonEncode(w)).toList(),
      );
    } catch (e) {
      debugPrint("⚠️ Failed to cache walls: $e");
    }
  }

  /// ✅ Load last wall from prefs
  Future<void> _loadLastWall() async {
    final savedWall = _prefs?.getString('lastSelectedWall');
    if (savedWall == null) return;
    try {
      final wallData = jsonDecode(savedWall) as Map<String, dynamic>;
      final wallId = wallData['appName'] as String?;
      if (wallId != null && wallId.isNotEmpty) {
        _enterWall(wallId);
      }
    } catch (e) {
      debugPrint("⚠️ Failed to decode lastSelectedWall: $e");
    }
  }

  /// ✅ Save last wall to prefs
  Future<void> _saveLastWall(String wall) async {
    final wallData = _findWall(wall);
    if (wallData == null) {
      debugPrint("⚠️ Tried to save wall '$wall' but not found in list");
      return;
    }
    try {
      final wallJson = jsonEncode(wallData);
      await _prefs?.setString('lastSelectedWall', wallJson);
      setState(() => lastWall = wall);
      debugPrint("💾 Saved wall to prefs: $wallJson");
    } catch (e) {
      debugPrint("⚠️ Save last wall failed: $e");
    }
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() => _locationDenied = true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _locationDenied = true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _locationDenied = false;
      });
    } catch (e) {
      debugPrint("⚠️ Location error: $e");
      if (!mounted) return;
      setState(() => _locationDenied = true);
    }
  }

  /// ✅ Dropbox assets fetch
  Future<void> _tryFetchOrCacheWallAssets(String wallId) async {
    try {
      final files = [
        {"remote": "/$wallId/MirrorDic.txt", "local": "MirrorDic.txt"},
        {"remote": "/$wallId/holdlist.csv", "local": "holdlist.csv"},
        {"remote": "/$wallId/dicholdlist.txt", "local": "dicholdlist.txt"},
        {"remote": "/$wallId/Settings", "local": "Settings"},
        {"remote": "/$wallId/wall.png", "local": "wall.png"},
      ];
      for (final f in files) {
        await dropboxFileService.downloadAndCacheFile(
          wallId,
          f["remote"]!,
          f["local"]!,
        );
      }
    } catch (e) {
      debugPrint("⚠️ Failed Dropbox assets for $wallId: $e");
    }
  }

  Future<List<String>> _loadSuperusers(String wallId) async {
    try {
      final file = await _getLocalWallFile(wallId, "Settings");
      if (!await file.exists()) return [];
      final lines = await file.readAsLines();

      // 👇 adjust index if needed, in your example the superuser line was near the bottom
      // here we take the first line that contains commas and no "hold"
      final superuserLine = lines.firstWhere(
        (line) => line.contains(",") && !line.contains("hold"),
        orElse: () => "",
      );

      if (superuserLine.isEmpty) return [];
      return superuserLine
          .split(",")
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint("⚠️ Failed to parse superusers for $wallId: $e");
      return [];
    }
  }

  /// ✅ Enter wall (sequential loading with overlay)
  Future<void> _enterWall(String wall) async {
    setState(() {
      _isLoadingWall = true;
      _loadingMessage = "🔄 Please wait...\n📋 Loading wall info...";
    });

    await _saveLastWall(wall);
    setState(() => selectedWall = wall);

    final wallData = _findWall(wall);
    if (wallData != null) {
      final lat = double.tryParse(wallData['lat'] ?? '');
      final lon = double.tryParse(wallData['lon'] ?? '');
      if (lat != null && lon != null) {
        _mapController.move(LatLng(lat, lon), 14.0);
      }
      final activeFlag = int.tryParse(wallData['active'] ?? '0') ?? 0;
      if (activeFlag == 1 || activeFlag == 2) {
        ProblemUpdaterService.instance.connect();
      } else {
        ProblemUpdaterService.instance.disconnect();
      }
    }

    final api = context.read<ApiService>();

    // Step 1: Info
    setState(() => _loadingMessage = "📋 Loading wall info...");
    await _tryFetchOrCacheTicks(api, wall);
    await _tryFetchOrCacheLikes(api, wall);
    await _tryFetchOrCacheSessions(api, wall);

    // Step 2: Assets
    setState(() => _loadingMessage = "🖼️ Loading wall image...");
    await _tryFetchOrCacheWallAssets(wall);

    // Step 3: Test file
    setState(() => _loadingMessage = "✅ Finalizing...");
    await _refreshTestFile(wall);

    // Step 4: Draft check
    final hasDrafts = await _hasDrafts(wall);
    debugPrint("📂 Drafts check for $wall => $hasDrafts");

    if (!mounted) return;

    setState(() {
      _hasWallDrafts = hasDrafts;
      _isLoadingWall = false;
    });

    // ✅ keep old entries, only update this wall
    final superusers = await _loadSuperusers(wall);
    setState(() {
      _wallSuperusers[wall] = superusers;
    });
    ;
  }

  Future<void> _refreshTestFile(String wallId) async {
    try {
      final auth = context.read<AuthState>();
      final username = auth.username ?? "guest";
      final raw = await context.read<ApiService>().getWallTestFile(
        wallId,
        username,
      );
      final testFile = await _getLocalWallFile(wallId, 'test.csv');
      await testFile.writeAsString(raw);
      await _prefs?.setString('test_$wallId', raw);
    } catch (e) {
      final testFile = await _getLocalWallFile(wallId, 'test.csv');
      if (await testFile.exists()) {
        try {
          final raw = await testFile.readAsString();
          await _prefs?.setString('test_$wallId', raw);
        } catch (_) {}
      }
    }
  }

  Future<void> _tryFetchOrCacheTicks(ApiService api, String wallId) async {
    try {
      final ticks = await api
          .getWallTicks(wallId)
          .timeout(const Duration(seconds: 10));
      await _prefs?.setString('ticks_$wallId', jsonEncode(ticks));
    } catch (e) {
      debugPrint("⚠️ Ticks error: $e");
    }
  }

  Future<void> _tryFetchOrCacheLikes(ApiService api, String wallId) async {
    try {
      final auth = context.read<AuthState>();
      final username = auth.username ?? "guest";
      final likesResponse = await api
          .getWallLikes(wallId, username)
          .timeout(const Duration(seconds: 10));
      if (likesResponse is Map) {
        final aggregated = (likesResponse['aggregated'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final userLikes = likesResponse['user'] as Map? ?? {};
        await _prefs?.setString(
          'likes_$wallId',
          jsonEncode({"aggregated": aggregated, "user": userLikes}),
        );
      }
    } catch (e) {
      debugPrint("⚠️ Likes error: $e");
    }
  }

  Future<void> _tryFetchOrCacheSessions(ApiService api, String wallId) async {
    if (!mounted) return;
    setState(() => _loadingSessions = true);
    try {
      final auth = context.read<AuthState>();
      final username = auth.username ?? "guest";
      final rawSessions = await api
          .getSessions(wallId, username)
          .timeout(const Duration(seconds: 10));
      if (rawSessions is List) {
        final sessions = rawSessions
            .map<Session>((s) => Session.fromJson(s))
            .toList();
        if (mounted) setState(() => _sessions = sessions);
      }
    } catch (e) {
      debugPrint("⚠️ Sessions error: $e");
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(
              selectedWall == null
                  ? "Select a Wall"
                  : "${_findWall(selectedWall!)?['userName'] ?? 'Unknown Wall'} Selected",
            ),
            actions: [
              IconButton(
                tooltip: "Log out",
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await auth.logout();
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
              ),
            ],
          ),

          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (walls.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else
                  Container(
                    constraints: const BoxConstraints(
                      minHeight: 56,
                      maxHeight: 70,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton2<String>(
                        isExpanded: true,
                        hint: const Text('Select a wall'),

                        // ----------------------------------------------------------------------
                        // 🔍 Search logic (unchanged)
                        // ----------------------------------------------------------------------
                        dropdownSearchData: DropdownSearchData(
                          searchController: _searchController,
                          searchInnerWidgetHeight: 60,
                          searchInnerWidget: Padding(
                            padding: const EdgeInsets.all(8),
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: 'Search walls...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          searchMatchFn: (item, searchValue) {
                            final wall = walls.firstWhere(
                              (w) => w['appName'] == item.value,
                              orElse: () => {},
                            );
                            return (wall['userName'] ?? "")
                                    .toLowerCase()
                                    .contains(searchValue.toLowerCase()) ||
                                (wall['appName'] ?? "").toLowerCase().contains(
                                  searchValue.toLowerCase(),
                                );
                          },
                        ),

                        // ----------------------------------------------------------------------
                        // 🎨 Dropdown styling (unchanged)
                        // ----------------------------------------------------------------------
                        dropdownStyleData: const DropdownStyleData(
                          useSafeArea: true,
                          elevation: 8,
                        ),
                        menuItemStyleData: const MenuItemStyleData(height: 48),
                        buttonStyleData: const ButtonStyleData(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            border: Border.fromBorderSide(
                              BorderSide(color: Colors.grey),
                            ),
                          ),
                        ),

                        // ----------------------------------------------------------------------
                        // 📌 WALL LIST ITEMS (THIS IS THE PART YOU WANTED!)
                        // ----------------------------------------------------------------------
                        items: _buildWallDropdownItems(),

                        onChanged: (value) {
                          if (value != null) _enterWall(value.trim());
                        },
                      ),
                    ),
                  ),

                // ✅ Nearest wall banner
                if (_highlightWall != null && selectedWall == null) ...[
                  const SizedBox(height: 10),
                  _nearestWallBanner(),
                ],

                const SizedBox(height: 16),
                if (_userPosition != null || selectedWall != null) ...[
                  _buildMap(),
                  const SizedBox(height: 24),
                ] else if (_locationDenied) ...[
                  Container(
                    height: MediaQuery.of(context).size.height / 3,
                    alignment: Alignment.center,
                    child: const Text(
                      "Location permission denied.\nEnable it to see nearby walls on the map.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  const SizedBox(height: 24),
                ],

                if (selectedWall != null)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _menuButton(
                            label: "Load Problems",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LoadProblemsPage(
                                    wallId: selectedWall!,
                                    superusers:
                                        _wallSuperusers[selectedWall!] ?? [],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Only for logged-in users
                          if (!auth.isGuest) ...[
                            // ✅ Create Problem
                            _menuButton(
                              label: "Create Problem",
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CreateProblemPage(
                                      wallId: selectedWall!,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            if (_hasWallDrafts) ...[
                              _menuButton(
                                label: "Draft Problems",
                                onPressed: () async {
                                  final dir =
                                      await getApplicationDocumentsDirectory();
                                  final draftFile = File(
                                    "${dir.path}/${selectedWall!}_drafts.csv",
                                  );
                                  if (!await draftFile.exists() ||
                                      (await draftFile.readAsLines()).isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "No draft problems found.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LoadProblemsPage(
                                        wallId: selectedWall!,
                                        isDraftMode: true,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                            ],

                            _menuButton(
                              label: "Log Book",
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LogBookAndLeaderboardPage(
                                      wallId: selectedWall!,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            // Optional hint for guest users
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                "Logbook, Drafts, and Create features require login.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ],

                          // Always visible
                          _menuButton(
                            label: "Settings",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ✅ Loading overlay
        // ✅ Loading overlay
        if (_isLoadingWall)
          AnimatedOpacity(
            opacity: _isLoadingWall ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              color: Colors.black54,
              child: Center(
                child: AnimatedScale(
                  scale: _isLoadingWall ? 1.0 : 0.8,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 10,
                    margin: const EdgeInsets.all(32),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text(
                            _loadingMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ✅ Cancel button
                          ElevatedButton.icon(
                            icon: const Icon(Icons.close),
                            label: const Text("Cancel"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _isLoadingWall = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
