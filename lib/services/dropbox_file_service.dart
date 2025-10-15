import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

    return file;
  }
}
