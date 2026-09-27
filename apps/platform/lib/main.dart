import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:varanasi_core/varanasi_core.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

import 'home_screen.dart';

void main() {
  final config = AppConfig.fromEnvironment(appName: 'platform');
  setupLogging(appName: config.appName);
  final tokens = TokenStore();
  final api = ApiClient(baseUrl: config.apiBaseUrl, tokens: tokens);
  runApp(PlatformApp(api: api, tokens: tokens));
}

class PlatformApp extends StatefulWidget {
  const PlatformApp({required this.api, required this.tokens, super.key});

  final ApiClient api;
  final TokenStore tokens;

  @override
  State<PlatformApp> createState() => _PlatformAppState();
}

class _PlatformAppState extends State<PlatformApp> {
  late final GoRouter _router = buildAppRouter(
    tokens: widget.tokens,
    // Sign-in arrives with the Platform auth module; until then every route is open.
    requireSignIn: false,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => HomeScreen(api: widget.api),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Varanasi Platform',
      theme: buildVaranasiTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
