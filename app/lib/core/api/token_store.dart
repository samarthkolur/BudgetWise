import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the session lives on the device.
///
/// A hosted auth vendor would persist and refresh the session for us; with our
/// own API that is our problem. Tokens go in the platform keystore — Keychain on iOS,
/// EncryptedSharedPreferences on Android — rather than in SharedPreferences,
/// because a refresh token is a bearer credential valid for sixty days and
/// plain preferences are readable on a rooted device.
///
/// The in-memory copy exists so the common path costs nothing: the keystore is
/// a platform channel round trip, and every API call would otherwise pay for it.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android encrypts by default now; the old
            // encryptedSharedPreferences flag is deprecated and ignored.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'budgetwise.accessToken';
  static const _refreshKey = 'budgetwise.refreshToken';

  String? _access;
  String? _refresh;
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _access = await _storage.read(key: _accessKey);
    _refresh = await _storage.read(key: _refreshKey);
    _loaded = true;
  }

  Future<String?> get accessToken async {
    await _load();
    return _access;
  }

  Future<String?> get refreshToken async {
    await _load();
    return _refresh;
  }

  Future<bool> get hasSession async => await refreshToken != null;

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
    _loaded = true;
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  /// Forgets the session on this device.
  ///
  /// Revoking server-side is the caller's job — this only clears local state,
  /// and clearing it must never fail in a way that strands someone signed in.
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _loaded = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
