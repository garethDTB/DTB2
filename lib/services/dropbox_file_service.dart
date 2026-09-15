import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dropbox_auth_service.dart';

class DropboxFileService {
  final DropboxAuthService authService;

  DropboxFileService(this.authService);

  /// Download a file from Dropbox and save it to local app storage
  Future<File> downloadAndCacheFile(
    String wallId,
    String dropboxPath,
    String localFilename,
  ) async {
    final token = await authService.getAccessToken();

    final response = await http.post(
      Uri.parse("https://content.dropboxapi.com/2/files/download"),
      headers: {
        "Authorization": "Bearer $token",
        "Dropbox-API-Arg": jsonEncode({"path": dropboxPath}),
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to download $dropboxPath: ${response.body}");
    }

    final dir = await getApplicationDocumentsDirectory();
    final wallDir = Directory("${dir.path}/walls/$wallId");
    if (!await wallDir.exists()) {
      await wallDir.create(recursive: true);
    }

    final file = File("${wallDir.path}/$localFilename");
    await file.writeAsBytes(response.bodyBytes);

    // ------------------------------------------------------------
    // Save the Dropbox revision that came with this download
    // ------------------------------------------------------------

    try {
      final apiResultHeader = response.headers["dropbox-api-result"];

      if (apiResultHeader != null) {
        final metadata = jsonDecode(apiResultHeader);
        final rev = metadata["rev"];

        if (rev != null) {
          final revFile = File("${file.path}.rev");
          await revFile.writeAsString(rev.toString());

          print("Saved Dropbox revision for $localFilename: $rev");
        }
      }
    } catch (e) {
      print("Could not save Dropbox revision for $localFilename: $e");
    }

    return file;
  }

  /// Check whether the cached local file is older/different
  /// from the current Dropbox file.
  Future<bool> cachedFileNeedsUpdate(String dropboxPath, File localFile) async {
    // No local file = definitely download it.
    if (!await localFile.exists()) {
      return true;
    }

    final revFile = File("${localFile.path}.rev");

    // Existing installs won't have .rev files yet.
    // Force one download to establish the revision.
    if (!await revFile.exists()) {
      return true;
    }

    final localRev = (await revFile.readAsString()).trim();

    final remoteRev = await getFileRevision(dropboxPath);

    return localRev != remoteRev;
  }

  Future<void> uploadFile(String dropboxPath, File localFile) async {
    final token = await authService.getAccessToken();

    if (!await localFile.exists()) {
      throw Exception("Local file does not exist: ${localFile.path}");
    }

    final bytes = await localFile.readAsBytes();

    final response = await http.post(
      Uri.parse("https://content.dropboxapi.com/2/files/upload"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/octet-stream",
        "Dropbox-API-Arg": jsonEncode({
          "path": dropboxPath,
          "mode": "overwrite",
          "autorename": false,
          "mute": false,
        }),
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to upload $dropboxPath: ${response.body}");
    }
  }

  /// Get Dropbox's revision ID for a file without downloading the file.
  Future<String> getFileRevision(String dropboxPath) async {
    final token = await authService.getAccessToken();

    final response = await http.post(
      Uri.parse("https://api.dropboxapi.com/2/files/get_metadata"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "path": dropboxPath,
        "include_media_info": false,
        "include_deleted": false,
        "include_has_explicit_shared_members": false,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to get metadata for $dropboxPath: ${response.body}",
      );
    }

    final data = jsonDecode(response.body);

    final rev = data["rev"];

    if (rev == null) {
      throw Exception("Dropbox did not return a revision for $dropboxPath");
    }

    return rev.toString();
  }

  Future<List<int>> downloadFileBytes(String dropboxPath) async {
    final token = await authService.getAccessToken();

    final response = await http.post(
      Uri.parse("https://content.dropboxapi.com/2/files/download"),
      headers: {
        "Authorization": "Bearer $token",
        "Dropbox-API-Arg": jsonEncode({"path": dropboxPath}),
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to download $dropboxPath: ${response.body}");
    }

    return response.bodyBytes;
  }

  Future<bool> localFileDiffersFromDropbox(
    String dropboxPath,
    File localFile,
  ) async {
    if (!await localFile.exists()) {
      throw Exception("Local file does not exist: ${localFile.path}");
    }

    final localBytes = await localFile.readAsBytes();

    final remoteBytes = await downloadFileBytes(dropboxPath);

    if (localBytes.length != remoteBytes.length) {
      return true;
    }

    for (int i = 0; i < localBytes.length; i++) {
      if (localBytes[i] != remoteBytes[i]) {
        return true;
      }
    }

    return false;
  }
}
