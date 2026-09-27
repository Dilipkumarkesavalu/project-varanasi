import 'package:flutter_test/flutter_test.dart';
import 'package:varanasi_core/varanasi_core.dart';

void main() {
  test('an explicit API URL is used as given', () {
    expect(
      AppConfig.resolveApiBaseUrl('http://localhost:8000'),
      Uri.parse('http://localhost:8000'),
    );
  });

  test('"/" means the origin the app was loaded from', () {
    final page = Uri.parse('https://staging.example.test/billing/#/invoices');

    expect(
      AppConfig.resolveApiBaseUrl('/', pageUrl: page),
      Uri.parse('https://staging.example.test'),
    );
  });
}
