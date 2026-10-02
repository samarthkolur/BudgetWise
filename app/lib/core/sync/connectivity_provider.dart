import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device has a network interface up — wifi or mobile data, not a
/// guarantee the internet beyond it is reachable. Good enough to decide "is it
/// worth trying to sync now", which is the only thing this app uses it for;
/// an actual sync attempt is what finds out whether the API can really be
/// reached, the same as any other API call already does.
final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);
