import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varanasi_core/varanasi_core.dart';

void main() {
  test('TokenStore notifies on sign-in and sign-out only when it changes', () {
    final tokens = TokenStore();
    var notified = 0;
    tokens.addListener(() => notified++);

    tokens
      ..setAccessToken('a')
      ..setAccessToken('a')
      ..clear()
      ..clear();

    expect(notified, 2);
    expect(() => tokens.setAccessToken(''), throwsArgumentError);
  });

  test('safeRedirectTarget never leaves the app', () {
    expect(safeRedirectTarget('/invoices?page=2', '/'), '/invoices?page=2');
    expect(safeRedirectTarget('https://evil.example', '/'), '/');
    expect(safeRedirectTarget('//evil.example', '/'), '/');
    expect(safeRedirectTarget(null, '/home'), '/home');
  });

  testWidgets(
    'signed-out users are sent to sign-in, then back after signing in',
    (tester) async {
      final tokens = TokenStore();
      final router = buildAppRouter(
        tokens: tokens,
        homePath: '/reports',
        routes: [
          GoRoute(path: '/reports', builder: (_, _) => const Text('Reports')),
          GoRoute(path: '/sign-in', builder: (_, _) => const Text('Sign in')),
        ],
      );

      await tester.pumpWidget(
        WidgetsApp.router(routerConfig: router, color: const Color(0xFF000000)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['from'],
        '/reports',
      );

      tokens.setAccessToken('tok');
      await tester.pumpAndSettle();
      expect(find.text('Reports'), findsOneWidget);
    },
  );

  test('ids have the documented formats', () {
    expect(newCorrelationId(), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(newIdempotencyKey(), isNot(newIdempotencyKey()));
  });
}
