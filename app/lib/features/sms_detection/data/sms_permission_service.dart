import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Requests and checks the OS `READ_SMS` permission.
///
/// A thin wrapper rather than calling `permission_handler` directly from the
/// controller/UI, so the Android-only guard lives in exactly one place: every
/// other platform is `false` without ever touching the plugin, which has no
/// iOS implementation for this permission to ask about.
class SmsPermissionService {
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    return Permission.sms.isGranted;
  }

  /// Returns the full [PermissionStatus] rather than a bool, because the
  /// caller needs to tell "denied" apart from "permanently denied/restricted"
  /// — the latter is what Android's Restricted Settings shows for a sideloaded
  /// app, and it needs a different message (open Settings, not just "deny").
  Future<PermissionStatus> request() async {
    if (!Platform.isAndroid) return PermissionStatus.denied;
    return Permission.sms.request();
  }
}
