import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// A backup file in the "CueBill backups" Drive folder.
class DriveFile {
  const DriveFile({required this.id, required this.name, required this.createdTime, required this.size});

  final String id;
  final String name;
  final DateTime createdTime;
  final int size;

  factory DriveFile.from(drive.File f) => DriveFile(
    id: f.id!,
    name: f.name ?? 'backup',
    createdTime: (f.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
    size: int.tryParse(f.size ?? '') ?? 0,
  );
}

/// Google Drive calls for backups. Uses the `drive.file` scope, so it only sees files CueBill created.
class DriveBackup {
  DriveBackup(http.Client client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;

  static const scopes = [drive.DriveApi.driveFileScope];
  static const folderName = 'CueBill backups';
  static const folderMime = 'application/vnd.google-apps.folder';
  static const fileMime = 'application/x-sqlite3';

  /// `cuebill-backup-2026-11-06-2130.sqlite`
  static String fileName(DateTime at) => 'cuebill-backup-${DateFormat('yyyy-MM-dd-HHmm').format(at)}.sqlite';

  Future<String> accountEmail() async {
    final about = await _api.about.get($fields: 'user(emailAddress)');
    return about.user?.emailAddress ?? 'your Google account';
  }

  /// Returns the backup folder's ID, creating the folder if needed. [knownId] is the cached ID, if any.
  Future<String> ensureFolder([String? knownId]) async {
    if (knownId != null) {
      try {
        final f = await _api.files.get(knownId, $fields: 'id,trashed') as drive.File;
        if (f.trashed != true) return knownId;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final found = await _api.files.list(
      q: "mimeType='$folderMime' and name='$folderName' and trashed=false",
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id)',
    );
    final existing = found.files?.firstOrNull?.id;
    if (existing != null) return existing;
    final created = await _api.files.create(
      drive.File(name: folderName, mimeType: folderMime),
      $fields: 'id',
    );
    return created.id!;
  }

  Future<DriveFile> upload(String folderId, Uint8List bytes, String name) async {
    final created = await _api.files.create(
      drive.File(name: name, parents: [folderId], mimeType: fileMime),
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: fileMime),
      $fields: 'id,name,createdTime,size',
    );
    return DriveFile.from(created);
  }

  /// Backups in the folder, newest first.
  Future<List<DriveFile>> list(String folderId) async {
    final files = <DriveFile>[];
    String? page;
    do {
      final res = await _api.files.list(
        q: "'$folderId' in parents and trashed=false and mimeType!='$folderMime'",
        spaces: 'drive',
        orderBy: 'createdTime desc',
        pageSize: 100,
        pageToken: page,
        $fields: 'nextPageToken,files(id,name,createdTime,size)',
      );
      files.addAll((res.files ?? const <drive.File>[]).where((f) => f.id != null).map(DriveFile.from));
      page = res.nextPageToken;
    } while (page != null);
    files.sort((a, b) => b.createdTime.compareTo(a.createdTime));
    return files;
  }

  Future<Uint8List> download(String id) async {
    final media = await _api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Deletes all but the newest [keep] backups. Returns how many were deleted.
  Future<int> prune(String folderId, {int keep = 30}) async {
    final old = (await list(folderId)).skip(keep).toList();
    for (final f in old) {
      await _api.files.delete(f.id);
    }
    return old.length;
  }
}
