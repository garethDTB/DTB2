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
import 'create_problem_page.dart';

// 👇 Global RouteObserver
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> clearAllWallData() async {
  final dir = await getApplicationDocumentsDirectory();
  final wallsDir = Directory('${dir.path}/walls');
  if (await wallsDir.exists()) {
    await wallsDir.delete(recursive: true);
    debugPrint("🧹 Cleared all wall data in ${wallsDir.path}");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) await clearAllWallData();

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
      ProblemUpdaterService.instance.connect();
    } else if (state == AppLifecycleState.paused) {
      ProblemUpdaterService.instance.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    final router = GoRouter(
      initialLocation: '/login',
      observers: [
        routeObserver, // 👈 THIS WORKS in go_router 14.x
      ],
      redirect: (context, state) {
        final loggedIn = auth.isLoggedIn;
        final guest = auth.isGuest;
        final loggingIn = state.matchedLocation == '/login';

        if (!loggedIn && !guest) return loggingIn ? null : '/login';
        if ((loggedIn || guest) && loggingIn) return '/wall-log';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
        GoRoute(path: '/wall-log', builder: (_, __) => const WallLogPage()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),

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

        GoRoute(
          path: '/create',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;

            return CreateProblemPage(
              wallId: extra?['wallId'] ?? '',
              isDraftMode: extra?['isDraftMode'] ?? false,
              isEditing: extra?['isEditing'] ?? false,
              problemRow: (extra?['problemRow'] as List?)?.cast<String>(),
              draftRow: (extra?['draftRow'] as List?)?.cast<String>(),
            );
          },
        ),
      ],
    );

    return MaterialApp.router(
      title: 'ClimbLight',
      debugShowCheckedModeBanner: false,

      // 👇 DO NOT add onGenerateRoute or routes here!
      routerConfig: router,

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),

      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaleFactor: mq.textScaleFactor.clamp(1.0, 1.3),
          ),
          child: child!,
        );
      },
    );
  }
}
