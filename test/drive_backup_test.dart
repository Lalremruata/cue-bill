import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cue_bill/data/store.dart';
import 'package:cue_bill/services/checkout.dart';
import 'package:cue_bill/services/drive_auth.dart';
import 'package:cue_bill/services/drive_backup.dart';
import 'package:cue_bill/services/drive_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A tiny in-memory Google Drive (files.list / create / get / delete) for MockClient.
class FakeDrive {
  final files = <Map<String, dynamic>>[]; // id, name, mimeType, parents, createdTime, size, bytes
  final requests = <http.Request>[];
  Object? failWith; // throw this (or return this status) on the next request
  int _id = 0;

  http.Client client() => MockClient(handle);

  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    final fail = failWith;
    if (fail is int) {
      return http.Response(
        jsonEncode({
          'error': {'code': fail, 'message': 'fail'},
        }),
        fail,
      );
    }
    if (fail != null) throw fail;
    final path = req.url.path;
    final json = {'content-type': 'application/json'};

    if (req.method == 'GET' && path == '/drive/v3/files') {
      final q = req.url.queryParameters['q'] ?? '';
      var list = files.where((f) => true).toList();
      if (q.contains("name='CueBill backups'")) {
        list = list.where((f) => f['mimeType'] == DriveBackup.folderMime).toList();
      } else {
        final parent = RegExp(r"'([^']+)' in parents").firstMatch(q)!.group(1);
        list = list.where((f) => (f['parents'] as List).contains(parent)).toList();
      }
      // Two results per page, to exercise paging.
      final start = int.tryParse(req.url.queryParameters['pageToken'] ?? '') ?? 0;
      final page = list.skip(start).take(2).toList();
      return http.Response(
        jsonEncode({
          'files': [for (final f in page) Map.of(f)..remove('bytes')],
          if (start + 2 < list.length) 'nextPageToken': '${start + 2}',
        }),
        200,
        headers: json,
      );
    }
    if (req.method == 'POST' && path == '/drive/v3/files') {
      final meta = jsonDecode(req.body) as Map<String, dynamic>;
      final f = {
        'id': 'f${++_id}',
        'parents': <String>[],
        ...meta,
        'createdTime': DateTime.now().toUtc().toIso8601String(),
      };
      files.add(f);
      return http.Response(jsonEncode(f), 200, headers: json);
    }
    if (req.method == 'POST' && path == '/upload/drive/v3/files') {
      // multipart/related: JSON metadata part, then the file bytes.
      final body = latin1.decode(req.bodyBytes);
      final meta = jsonDecode(RegExp(r'\{.*?\}\s', dotAll: true).firstMatch(body)!.group(0)!) as Map<String, dynamic>;
      final f = {
        'id': 'f${++_id}',
        ...meta,
        'createdTime': DateTime.now().add(Duration(seconds: _id)).toUtc().toIso8601String(),
        'size': '${req.bodyBytes.length}',
        'bytes': req.bodyBytes,
      };
      files.add(f);
      return http.Response(jsonEncode(Map.of(f)..remove('bytes')), 200, headers: json);
    }
    final id = path.split('/').last;
    if (req.method == 'GET' && path.startsWith('/drive/v3/files/')) {
      final f = files.where((f) => f['id'] == id).firstOrNull;
      if (f == null) return http.Response('{"error":{"code":404,"message":"not found"}}', 404, headers: json);
      if (req.url.queryParameters['alt'] == 'media') {
        return http.Response.bytes(
          f['restoreBytes'] as List<int>,
          200,
          headers: {'content-type': DriveBackup.fileMime},
        );
      }
      return http.Response(jsonEncode({'id': id, 'trashed': false}), 200, headers: json);
    }
    if (req.method == 'DELETE') {
      files.removeWhere((f) => f['id'] == id);
      return http.Response('', 204);
    }
    return http.Response('unexpected ${req.method} $path', 500);
  }
}

class FakeAuth implements DriveAuth {
  FakeAuth(this.drive);
  final FakeDrive drive;
  String? email = 'counter@example.com';

  @override
  Future<String?> restore() async => email;
  @override
  Future<String> signIn() async => email = 'counter@example.com';
  @override
  Future<void> signOut() async => email = null;
  @override
  Future<http.Client> client() async => drive.client();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('DriveBackup', () {
    test('finds or creates the backup folder', () async {
      final fake = FakeDrive();
      final api = DriveBackup(fake.client());
      final id = await api.ensureFolder();
      expect(fake.files.single['name'], 'CueBill backups');
      expect(fake.files.single['mimeType'], DriveBackup.folderMime);
      expect(await api.ensureFolder(), id, reason: 'reuses the existing folder');
      expect(await api.ensureFolder(id), id, reason: 'checks the cached ID');
      expect(fake.files.length, 1);
    });

    test('uploads into the folder with the right name and type', () async {
      final fake = FakeDrive();
      final api = DriveBackup(fake.client());
      final folder = await api.ensureFolder();
      final name = DriveBackup.fileName(DateTime(2026, 11, 6, 21, 30));
      expect(name, 'cuebill-backup-2026-11-06-2130.sqlite');
      final file = await api.upload(folder, Uint8List.fromList(List.filled(500, 1)), name);
      final upload = fake.requests.last;
      expect(upload.url.queryParameters['uploadType'], 'multipart');
      expect(file.name, name);
      expect(fake.files.last['parents'], [folder]);
      expect(fake.files.last['mimeType'], DriveBackup.fileMime);
    });

    test('lists newest first across pages and prunes to the newest N', () async {
      final fake = FakeDrive();
      final api = DriveBackup(fake.client());
      final folder = await api.ensureFolder();
      for (var i = 0; i < 5; i++) {
        await api.upload(folder, Uint8List(10), 'b$i.sqlite');
      }
      final list = await api.list(folder);
      expect(list.map((f) => f.name), ['b4.sqlite', 'b3.sqlite', 'b2.sqlite', 'b1.sqlite', 'b0.sqlite']);
      expect(await api.prune(folder, keep: 3), 2);
      expect((await api.list(folder)).map((f) => f.name), ['b4.sqlite', 'b3.sqlite', 'b2.sqlite']);
    });
  });

  group('DriveSync', () {
    late Directory dir;
    late AppStore store;
    late FakeDrive fake;
    late FakeAuth auth;
    late DriveSync sync;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cuebill_drive');
      store = await AppStore.open(dbPath: '${dir.path}/d.sqlite', factory: databaseFactoryFfi, filesDir: dir.path);
      fake = FakeDrive();
      auth = FakeAuth(fake);
      sync = DriveSync(store, auth: auth);
      await sync.start();
    });

    tearDown(() async {
      sync.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });

    test('start() reconnects and runs the first daily backup', () async {
      expect(sync.connected, isTrue);
      expect(fake.files.where((f) => f['mimeType'] == DriveBackup.fileMime).length, 1);
      expect(store.settings.driveLastBackupAt, isNotNull);
      expect(store.settings.driveFolderId, isNotNull);
      expect(store.settings.lastBackupAt, isNotNull);
    });

    test('daily backup skips when already done today, switched off, or not connected', () async {
      expect(await sync.maybeAutoBackup(), isFalse, reason: 'already backed up today');
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await sync.setAutoBackup(false);
      expect(await sync.maybeAutoBackup(now: tomorrow), isFalse, reason: 'switched off');
      await sync.setAutoBackup(true);
      await sync.disconnect();
      expect(await sync.maybeAutoBackup(now: tomorrow), isFalse, reason: 'not connected');
      await sync.connect();
      expect(await sync.maybeAutoBackup(now: tomorrow), isTrue);
    });

    test('offline: clear message, stays connected; 401: asks to connect again', () async {
      fake.failWith = const SocketException('no network');
      await expectLater(sync.backupNow(), throwsA(isA<DriveAuthException>()));
      expect(sync.lastError, contains('No internet'));
      expect(sync.connected, isTrue);

      fake.failWith = 401;
      await expectLater(sync.backupNow(), throwsA(isA<DriveAuthException>()));
      expect(sync.lastError, contains('Connect again'));
      expect(sync.connected, isFalse);
    });

    test('restores a backup picked from Drive', () async {
      // Make one sale, take that backup as the Drive copy, then add more sales.
      await store.addItem(store.activeTables[2], store.menu.first);
      await store.completeSale(store.activeTables[2], const CheckoutOptions());
      final snapshot = await store.backupBytes();
      final file = (await sync.listBackups()).first;
      fake.files.firstWhere((f) => f['id'] == file.id)['restoreBytes'] = snapshot;
      await store.loadSampleSales();
      expect(store.invoiceCount, greaterThan(1));

      await sync.restoreFrom(file);
      expect(store.invoiceCount, 1);
    });
  });
}
