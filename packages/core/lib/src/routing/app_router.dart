import 'package:go_router/go_router.dart';

import '../auth/token_store.dart';

/// Builds the app's [GoRouter] with a sign-in guard.
///
/// - Routes listed in [publicPaths] (plus [signInPath]) are reachable without a token.
/// - Any other route redirects to [signInPath] with `?from=<original location>`.
/// - Once signed in, visiting [signInPath] goes to `from` (or [homePath]).
/// - The router re-evaluates whenever the [TokenStore] changes (sign-in, sign-out, 401).
GoRouter buildAppRouter({
  required List<RouteBase> routes,
  required TokenStore tokens,
  String homePath = '/',
  String signInPath = '/sign-in',
  Set<String> publicPaths = const {},
  bool requireSignIn = true,
}) {
  final open = {signInPath, ...publicPaths};
  return GoRouter(
    initialLocation: homePath,
    refreshListenable: tokens,
    routes: routes,
    redirect: (context, state) {
      if (!requireSignIn) return null;
      final path = state.uri.path;
      if (!tokens.isAuthenticated && !open.contains(path)) {
        return Uri(
          path: signInPath,
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (tokens.isAuthenticated && path == signInPath) {
        return safeRedirectTarget(state.uri.queryParameters['from'], homePath);
      }
      return null;
    },
  );
}

/// Only follow in-app paths after sign-in; never redirect to another site.
String safeRedirectTarget(String? from, String fallback) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return fallback;
  }
  return from;
}
