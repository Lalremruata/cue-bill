import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;

import '../data/store.dart';
import 'drive_auth.dart';
import 'drive_backup.dart';

/// Google Drive backups: connect, back up now, daily automatic backup, list and restore.
class DriveSync extends ChangeNotifier {
  DriveSync(this.store, {DriveAuth? auth, bool useDefaultAuth = true, DriveBackup Function(http.Client)? api})
    : auth = auth ?? (useDefaultAuth ? DriveAuth.forPlatform() : null),
      _api = api ?? DriveBackup.new;

  final AppStore store;

  /// Null when this build has no Google OAuth client IDs for the platform.
  final DriveAuth? auth;
  final DriveBackup Function(http.Client) _api;

  static const keep = 30;

  String? email;
  bool busy = false;
  String? lastError;
  Timer? _timer;

  bool get available => auth != null;
  bool get connected => email != null;

  /// Reconnects silently, then backs up if today's backup is still due. Checks again every hour.
  Future<void> start() async {
    if (auth == null) return;
    try {
      email = await auth!.restore();
    } catch (_) {
      email = null;
    }
    notifyListeners();
    await maybeAutoBackup();
    _timer ??= Timer.periodic(const Duration(hours: 1), (_) => maybeAutoBackup());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<T> _run<T>(Future<T> Function() task) async {
    if (auth == null) throw DriveAuthException('Google Drive is not set up in this build.');
    if (busy) throw DriveAuthException('A Google Drive task is already running.');
    busy = true;
    notifyListeners();
    try {
      final result = await task();
      lastError = null;
      return result;
    } catch (e) {
      lastError = friendlyError(e);
      if (_isAuthFailure(e)) email = null; // access expired or was removed: ask to connect again
      throw DriveAuthException(lastError!);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> connect() => _run(() async {
    email = await auth!.signIn();
  });

  Future<void> disconnect() async {
    if (auth == null) return;
    await auth!.signOut();
    email = null;
    lastError = null;
    notifyListeners();
  }

  Future<R> _withApi<R>(Future<R> Function(DriveBackup api) task) async {
    final client = await auth!.client();
    try {
      return await task(_api(client));
    } finally {
      client.close();
    }
  }

  Future<String> _folder(DriveBackup api) async {
    final id = await api.ensureFolder(store.settings.driveFolderId);
    if (id != store.settings.driveFolderId) await store.updateSettings((s) => s.driveFolderId = id);
    return id;
  }

  /// Uploads a copy of the database, then keeps only the newest [keep] backups on Drive.
  Future<DriveFile> backupNow() => _run(() async {
    if (!connected) throw DriveAuthException('Not connected to Google Drive.');
    final bytes = await store.backupBytes();
    final now = DateTime.now();
    return _withApi((api) async {
      final folder = await _folder(api);
      final file = await api.upload(folder, bytes, DriveBackup.fileName(now));
      await store.updateSettings((s) => s.driveLastBackupAt = now);
      try {
        await api.prune(folder, keep: keep);
      } catch (_) {
        // The backup is safe; pruning can wait for next time.
      }
      return file;
    });
  });

  /// The daily backup: only when connected, switched on, and not yet done today. Never throws.
  Future<bool> maybeAutoBackup({DateTime? now}) async {
    if (!connected || busy || !store.settings.driveAutoBackup) return false;
    final last = store.settings.driveLastBackupAt;
    final n = now ?? DateTime.now();
    if (last != null && last.year == n.year && last.month == n.month && last.day == n.day) return false;
    try {
      await backupNow();
      return true;
    } catch (_) {
      return false; // lastError is shown in Settings
    }
  }

  Future<void> setAutoBackup(bool on) => store.updateSettings((s) => s.driveAutoBackup = on);

  Future<List<DriveFile>> listBackups() => _run(() => _withApi((api) async => api.list(await _folder(api))));

  /// Downloads a backup from Drive and replaces all data on this device with it.
  Future<void> restoreFrom(DriveFile file) => _run(() async {
    final bytes = await _withApi((api) => api.download(file.id));
    await store.restore(bytes);
  });

  static bool _isAuthFailure(Object e) =>
      (e is drive.DetailedApiRequestError && e.status == 401) ||
      e is gauth.ServerRequestFailedException ||
      e is gauth.AccessDeniedException ||
      (e is DriveAuthException && e.message.contains('Connect again'));

  /// Plain-English message for anything that can go wrong talking to Google.
  static String friendlyError(Object e) {
    if (e is DriveAuthException) return e.message;
    if (e is CueBillException) return e.message;
    if (e is SocketException || e is http.ClientException || e is HandshakeException || e is TimeoutException) {
      return 'No internet connection. Nothing was sent to Google Drive.';
    }
    if (e is gauth.ServerRequestFailedException || e is gauth.AccessDeniedException) {
      return 'Google Drive access has expired or was removed. Connect again.';
    }
    if (e is drive.DetailedApiRequestError) {
      return switch (e.status) {
        401 => 'Google Drive access has expired or was removed. Connect again.',
        403 when (e.message ?? '').toLowerCase().contains('storage') => 'Your Google Drive is full.',
        403 => 'Google Drive refused the request: ${e.message ?? 'permission denied'}.',
        404 => 'That backup is no longer on Google Drive.',
        _ => 'Google Drive error ${e.status}: ${e.message ?? 'try again later'}.',
      };
    }
    return 'Google Drive backup failed: $e';
  }
}
