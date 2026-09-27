import 'package:flutter/foundation.dart';

/// Holds the current access token in memory only.
///
/// ADR-0007 §11: access tokens are short-lived (15 min) and live in memory; the refresh
/// token is an `HttpOnly` cookie the app never sees. Nothing is written to local storage.
/// Listeners (e.g. the router) are notified when the user signs in or out.
class TokenStore extends ChangeNotifier {
  String? _accessToken;

  String? get accessToken => _accessToken;

  bool get isAuthenticated => _accessToken != null;

  void setAccessToken(String token) {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'must not be empty');
    }
    if (token == _accessToken) return;
    _accessToken = token;
    notifyListeners();
  }

  void clear() {
    if (_accessToken == null) return;
    _accessToken = null;
    notifyListeners();
  }
}
