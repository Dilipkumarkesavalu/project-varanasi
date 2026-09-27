import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varanasi_platform_app/main.dart';
import 'package:varanasi_core/varanasi_core.dart';
import 'package:varanasi_ui/varanasi_ui.dart';

ApiClient _api(http.Response response, TokenStore tokens) => ApiClient(
  baseUrl: Uri.parse('http://backend.test'),
  tokens: tokens,
  httpClient: MockClient((_) async => response),
);

void main() {
  testWidgets('sample screen shows backend status, form and table', (
    tester,
  ) async {
    final tokens = TokenStore();
    final ok = http.Response(jsonEncode({'status': 'ok'}), 200);
    await tester.pumpWidget(PlatformApp(api: _api(ok, tokens), tokens: tokens));
    await tester.pumpAndSettle();

    expect(find.text('Varanasi Platform'), findsOneWidget);
    expect(find.text('Backend status: ok'), findsOneWidget);
    expect(find.byType(VTextField), findsOneWidget);
    expect(find.text('Tenants (sample data)'), findsOneWidget);
    expect(find.text('Sharma Traders'), findsOneWidget);
  });

  testWidgets('shows the shared error view when the backend is down', (
    tester,
  ) async {
    final tokens = TokenStore();
    final down = http.Response(
      jsonEncode({
        'code': 'internal_error',
        'title': 'Server error',
        'correlation_id': 'req-x1',
      }),
      503,
    );
    await tester.pumpWidget(
      PlatformApp(api: _api(down, tokens), tokens: tokens),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend unreachable'), findsOneWidget);
    expect(find.text('Reference: req-x1'), findsOneWidget);
  });

  testWidgets('the form validates before submitting', (tester) async {
    final tokens = TokenStore();
    final ok = http.Response(jsonEncode({'status': 'ok'}), 200);
    await tester.pumpWidget(PlatformApp(api: _api(ok, tokens), tokens: tokens));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(VButton, 'Create tenant'));
    await tester.pumpAndSettle();

    expect(find.text('Organization name is required.'), findsOneWidget);
  });
}
