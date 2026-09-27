import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:varanasi_core/varanasi_core.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

import 'home_screen.dart';

void main() {
  final config = AppConfig.fromEnvironment(appName: 'billing');
  setupLogging(appName: config.appName);
  final tokens = TokenStore();
  final api = ApiClient(baseUrl: config.apiBaseUrl, tokens: tokens);
  runApp(BillingApp(api: api, tokens: tokens));
}

class BillingApp extends StatefulWidget {
  const BillingApp({required this.api, required this.tokens, super.key});

  final ApiClient api;
  final TokenStore tokens;

  @override
  State<BillingApp> createState() => _BillingAppState();
}

class _BillingAppState extends State<BillingApp> {
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
      title: 'Varanasi Billing',
      theme: buildVaranasiTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
