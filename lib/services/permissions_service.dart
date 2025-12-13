import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  static Future<bool> requestStoragePermissions(BuildContext context) async {
    try {
      // Request storage permissions
      final storageStatus = await Permission.storage.request();
      final audioStatus = await Permission.audio.request();

      if (storageStatus.isGranted || audioStatus.isGranted) {
        return true;
      }

      // If permissions are permanently denied, show dialog
      if (storageStatus.isPermanentlyDenied ||
          audioStatus.isPermanentlyDenied) {
        if (context.mounted) {
          await showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Permissions Required'),
                  content: const Text(
                    'Storage permissions are required to access your music library. '
                    'Please enable them in app settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        openAppSettings();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Open Settings'),
                    ),
                  ],
                ),
          );
        }
        return false;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
