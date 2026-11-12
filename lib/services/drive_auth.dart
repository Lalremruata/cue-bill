import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'drive_backup.dart';

/// OAuth client IDs, passed at build time with `--dart-define-from-file=google_oauth.json`.
/// See README → "Google Drive backups: one-time setup".
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  static const desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// The "Web application" client ID. Android sign-in needs it.
  static const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}

class DriveAuthException implements Exception {
  DriveAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Signs in to Google and hands out an HTTP client that can call Drive.
abstract class DriveAuth {
  /// The platform's sign-in, or null if this build has no OAuth client IDs for it.
  static DriveAuth? forPlatform() {
    if (Platform.isAndroid && GoogleOAuthConfig.serverClientId.isNotEmpty) return MobileDriveAuth();
    if (Platform.isIOS && GoogleOAuthConfig.iosClientId.isNotEmpty) return MobileDriveAuth();
    if ((Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
        GoogleOAuthConfig.desktopClientId.isNotEmpty &&
        GoogleOAuthConfig.desktopClientSecret.isNotEmpty) {
      return DesktopDriveAuth();
    }
    return null;
  }

  /// Reconnects silently at startup. Returns the account email, or null if not connected.
  Future<String?> restore();

  /// Asks the user to pick an account and allow Drive access. Returns the account email.
  Future<String> signIn();

  Future<void> signOut();

  /// A client authorised for [DriveBackup.scopes]. Close it when done.
  Future<http.Client> client();
}

/// Android and iOS: the native Google account picker.
class MobileDriveAuth implements DriveAuth {
  bool _initialized = false;
  GoogleSignInAccount? _account;

  GoogleSignIn get _gsi => GoogleSignIn.instance;

  Future<void> _init() async {
    if (_initialized) return;
    await _gsi.initialize(
      clientId: Platform.isIOS ? GoogleOAuthConfig.iosClientId : null,
      serverClientId: GoogleOAuthConfig.serverClientId.isEmpty ? null : GoogleOAuthConfig.serverClientId,
    );
    _initialized = true;
  }

  @override
  Future<String?> restore() async {
    await _init();
    _account = await (_gsi.attemptLightweightAuthentication() ?? Future<GoogleSignInAccount?>.value());
    if (_account == null) return null;
    // Still connected only if Drive access is still granted.
    final authz = await _account!.authorizationClient.authorizationForScopes(DriveBackup.scopes);
    return authz == null ? null : _account!.email;
  }

  @override
  Future<String> signIn() async {
    await _init();
    try {
      _account = await _gsi.authenticate(scopeHint: DriveBackup.scopes);
      await _account!.authorizationClient.authorizeScopes(DriveBackup.scopes);
      return _account!.email;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw DriveAuthException('Sign-in was cancelled.');
      throw DriveAuthException('Google sign-in failed: ${e.description ?? e.code.name}');
    }
  }

  @override
  Future<void> signOut() async {
    await _init();
    try {
      await _gsi.disconnect(); // also revokes Drive access
    } catch (_) {
      await _gsi.signOut();
    }
    _account = null;
  }

  @override
  Future<http.Client> client() async {
    final account = _account;
    if (account == null) throw DriveAuthException('Not connected to Google Drive.');
    // Asked fresh every time: the platform refreshes the short-lived token for us.
    final authz = await account.authorizationClient.authorizationForScopes(DriveBackup.scopes);
    if (authz == null) throw DriveAuthException('Google Drive access was removed. Connect again.');
    return authz.authClient(scopes: DriveBackup.scopes);
  }
}

/// Windows and macOS: Google sign-in in the browser, with a loopback redirect.
/// The refresh token is kept in the system keychain / credential store.
class DesktopDriveAuth implements DriveAuth {
  DesktopDriveAuth({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The legacy keychain works in a sandboxed app without a paid signing team.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _key = 'cuebill.google_drive';
  final FlutterSecureStorage _storage;
  gauth.AccessCredentials? _credentials;
  String? _email;

  static final _clientId = gauth.ClientId(GoogleOAuthConfig.desktopClientId, GoogleOAuthConfig.desktopClientSecret);

  Future<void> _save() async {
    final c = _credentials;
    if (c == null) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(key: _key, value: jsonEncode({'email': _email, 'credentials': c.toJson()}));
  }

  @override
  Future<String?> restore() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _credentials = gauth.AccessCredentials.fromJson(j['credentials'] as Map<String, dynamic>);
      _email = j['email'] as String?;
      return _credentials!.refreshToken == null ? null : _email;
    } catch (_) {
      await _storage.delete(key: _key);
      return null;
    }
  }

  @override
  Future<String> signIn() async {
    final base = http.Client();
    try {
      final credentials = await gauth
          .obtainAccessCredentialsViaUserConsent(
            _clientId,
            DriveBackup.scopes,
            base,
            (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            customPostAuthPage:
                '<html><body style="font-family:sans-serif;padding:40px">'
                '<h2>CueBill is connected to Google Drive.</h2><p>You can close this tab and go back to CueBill.</p>'
                '</body></html>',
          )
          .timeout(const Duration(minutes: 5));
      if (credentials.refreshToken == null) {
        throw DriveAuthException(
          'Google did not give CueBill lasting access. Remove CueBill at myaccount.google.com/permissions and connect again.',
        );
      }
      _credentials = credentials;
      final client = gauth.authenticatedClient(http.Client(), credentials);
      try {
        _email = await DriveBackup(client).accountEmail();
      } finally {
        client.close();
      }
      await _save();
      return _email!;
    } on TimeoutException {
      throw DriveAuthException('Sign-in timed out. Try again.');
    } on gauth.UserConsentException catch (e) {
      throw DriveAuthException('Google sign-in was not completed: ${e.message}');
    } finally {
      base.close();
    }
  }

  @override
  Future<void> signOut() async {
    final token = _credentials?.refreshToken ?? _credentials?.accessToken.data;
    if (token != null) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': token});
      } catch (_) {
        // Offline: the token is forgotten locally anyway.
      }
    }
    _credentials = null;
    _email = null;
    await _save();
  }

  @override
  Future<http.Client> client() async {
    final c = _credentials;
    if (c == null) throw DriveAuthException('Not connected to Google Drive.');
    final client = gauth.autoRefreshingClient(_clientId, c, http.Client());
    client.credentialUpdates.listen((updated) {
      _credentials = updated;
      _save();
    });
    return client;
  }
}
