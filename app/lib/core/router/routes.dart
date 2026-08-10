/// Route paths, held separately from the `GoRouter` setup so a screen can
/// depend on a path constant without pulling in every other screen the
/// router wires together.
abstract final class Routes {
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const dashboard = '/dashboard';
  static const ledger = '/ledger';
  static const goals = '/goals';
  static const insights = '/insights';
  static const settings = '/settings';
}
