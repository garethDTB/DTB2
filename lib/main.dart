// lib/main.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'auth_state.dart';
import 'app_state.dart';
import 'login_page.dart';
import 'wall_log_page.dart';
import 'settings_page.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'providers/problems_provider.dart';
import 'features/comments/presentation/comments_page.dart';

Future<void> clearAllWallData() async {
  final dir = await getApplicationDocumentsDirectory();
  final wallsDir = Directory('${dir.path}/walls');
  if (await wallsDir.exists()) {
    await wallsDir.delete(recursive: true);
    debugPrint("🧹 Cleared all wall data in ${wallsDir.path}");
  } else {
    debugPrint("ℹ️ No wall data found at ${wallsDir.path}");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🧹 Only clear wall data in debug mode
  if (kDebugMode) {
    await clearAllWallData();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => AppState()),
        Provider<ApiService>(
          create: (_) => ApiService(
            "https://dtb2-func-hkhagfe5gkfaa0g9.ukwest-01.azurewebsites.net/api",
          ),
        ),
        ChangeNotifierProvider(create: (_) => ProblemsProvider()),
      ],
      child: const ClimbLightApp(),
    ),
  );
}

class ClimbLightApp extends StatefulWidget {
  const ClimbLightApp({super.key});

  @override
  State<ClimbLightApp> createState() => _ClimbLightAppState();
}

class _ClimbLightAppState extends State<ClimbLightApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("📱 App resumed → reconnecting WebSocket...");
      ProblemUpdaterService.instance.connect();
    } else if (state == AppLifecycleState.paused) {
      print("📱 App paused → disconnecting WebSocket...");
      ProblemUpdaterService.instance.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    final router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final loggedIn = auth.isLoggedIn;
        final loggingIn = state.matchedLocation == '/login';

        if (!loggedIn) return loggingIn ? null : '/login';
        if (loggedIn && loggingIn) return '/wall-log';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
        GoRoute(path: '/wall-log', builder: (_, __) => const WallLogPage()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),

        // 👇 Comments route
        GoRoute(
          path: '/comments',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>;
            return CommentsPage(
              wallId: args["wallId"],
              problemName: args["problemName"],
              user: args["user"],
            );
          },
        ),
      ],
    );

    return MaterialApp.router(
      title: 'ClimbLight',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
