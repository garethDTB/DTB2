import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DropboxService {
  // 🔑 Replace this with your Dropbox access token
  static const String _accessToken =
      "sl.u.AF9pAzopLEE8oXKizxW5a8KfCKZvOQTMgSjLDLtM7WcletF4npsAO2lHm5yx8zQoeY5ykCw5muuDjJj1nYH6TjO46_ZeZS99Jo350eVX4uhFX1pc2tjjYJg52oSb24d9cCLcI9Wh7b4bTCECJn0SuuzwJF-7Bq7-H-C0fRpMFpbz6DqeuDSaUkX7yuny_svirDuzhSqnw5U-G150_OkQvAq4fMgkNoE09ZxYU6VXilDuUSWLk1xZ5rInN3QdgkWIRfUM3MJry9LQpTCirGAlZHFDX8WRJaYh3tVsp11ptJfz320dkTxhM2M2mZa_5f1UXAgbqlFbgp-3ZmLhFRj-YHWEEOdHG4DnIE0HOHMJ9UPmmlnMCKnlPOrj8zEM5utSeGU721eg0OapXwRMEGk5n-E59HKpN0g-jOr36APbOiTAmZcbtwBQoOg3jyUAJwp3moSvz9dc6cJhe6F-WMXWFtntAmabUkVcx_hwDJHBz5DucGFX1Uuqgyw_iRVmq7JveMW8Z7ITmTGZIqx1CyJTw_tFTf2xrXuGpBXQoXLV_Bi9US5YcXQzjSDMs0mMmM5chwxpQV9_EUZX2Gi3wmXuSo0cdnf1n08PbkKZU38f0-FX18Ewpjm1YEQPASw6b__kdrrh2GndnnKZ7x_IeZFXJpNr8VXD-o-eRKeVWVesgLj3HOwgsWnxxivPTmaUyJOEIn2eP43c9snFbv-2X-TJ3OOW2yajn0gwnsiEgNgsxxYntMhlOHJbEYrya7Gt7QOb_buZ06jmqwWI1Odi65jpOUCVnnsgM1SIZtuDyCYcX_UrDvzQkkVakqWb25Iw7lto5FrjFssOb-rOmEQDINmxi18Ei_IXrILRnvRWEITpkKvsNas1hWgse_LMoceik_Dno9sIGHoAI-Q63emkonKTwKLeQtW3o9z6F5WLocv0cv7nUzhy2EwO4CP3tRva112UPZ2-wbhFec6IqbuGusfaeab3nNulbsqF7xUYrAF1jizkyYbLptxOqfeEnlhkP4iN6T9D6qK6ga4MLFxE4rGbnns-JTY5XNlDywabX4F6C5R1z01HBloat1lXnH1Ky21T0oStPQptQbDsYVq1sVcmwd98JaiKQ21jD7e5vjThaCXx3yzQT9uIAejnNmAs2REl9Ua3miXVBkd-CBLqjEdJrELc5PtJxYrmiBY8mFJDc3QsQXIDgN5CqWJiUI0GnvyK_MkJK2Rk-lxJW_35Xm3pelVwZXFMv5BCww8-4gr3kX93D2NU6OJB6wKWjXihHr9lt5rp_cMCNvxd6xbxD3FuLfG6uYLkzbK-IZPfe7-dcsNqDg";

  /// Returns the local path for storing files.
  static Future<String> _localPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// Ensures a global file exists locally by downloading from Dropbox if needed.
  static Future<File?> ensureGlobalFile(
    String filename, {
    BuildContext? context,
  }) async {
    try {
      final localPath = await _localPath();
      final file = File('$localPath/$filename');

      if (!await file.exists()) {
        await _downloadFromDropbox(filename, file, context);
      }
      return file;
    } catch (e) {
      _showError(context, "Error ensuring global file $filename: $e");
      return null;
    }
  }

  /// Ensures a wall-specific file exists locally by downloading from Dropbox if needed.
  static Future<File?> ensureWallFile(
    String wallName,
    String filename, {
    BuildContext? context,
  }) async {
    try {
      final localPath = await _localPath();
      final wallDir = Directory('$localPath/$wallName');
      if (!await wallDir.exists()) {
        await wallDir.create(recursive: true);
      }

      final file = File('${wallDir.path}/$filename');

      if (!await file.exists()) {
        await _downloadFromDropbox('$wallName/$filename', file, context);
      }
      return file;
    } catch (e) {
      _showError(context, "Error ensuring wall file $filename: $e");
      return null;
    }
  }

  /// Downloads a file from Dropbox to local storage.
  static Future<void> _downloadFromDropbox(
    String dropboxPath,
    File localFile,
    BuildContext? context,
  ) async {
    try {
      final url = Uri.parse("https://content.dropboxapi.com/2/files/download");
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $_accessToken",
          "Dropbox-API-Arg": '{"path": "/Apps/DTB2/$dropboxPath"}',
        },
      );

      if (response.statusCode == 200) {
        await localFile.writeAsBytes(response.bodyBytes);
        debugPrint("Downloaded $dropboxPath → ${localFile.path}");
      } else {
        _showError(
          context,
          "Failed to download $dropboxPath (code ${response.statusCode})",
        );
      }
    } catch (e) {
      _showError(context, "Error downloading $dropboxPath: $e");
    }
  }

  /// Reads a file from local storage, returning its contents as a string.
  static Future<String?> readLocalFile(String filename) async {
    try {
      final localPath = await _localPath();
      final file = File('$localPath/$filename');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      debugPrint("Error reading local file $filename: $e");
      return null;
    }
  }

  /// Helper: show error message with a snackbar.
  static void _showError(BuildContext? context, String message) {
    debugPrint(message);
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
