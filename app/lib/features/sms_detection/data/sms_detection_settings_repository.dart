import 'package:budgetwise/core/db/local_database.dart';

/// The single on/off switch and scan checkpoint for SMS detection.
///
/// One row (`id = 1`), upserted rather than replaced — a plain
/// `INSERT OR REPLACE` would silently null out whichever column isn't part
/// of a given write (flipping the switch would erase the scan checkpoint,
/// and vice versa), which is the kind of bug that only shows up as "why did
/// it rescan three months of SMS after I toggled the setting".
class SmsDetectionSettingsRepository {
  SmsDetectionSettingsRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  Future<bool> isEnabled() async {
    final row = await _row();
    return row != null && (row['enabled']! as int) == 1;
  }

  Future<void> setEnabled({required bool enabled}) async {
    final db = (await _dbFuture).db;
    await db.rawInsert(
      'INSERT INTO sms_detection_settings (id, enabled) VALUES (1, ?) '
      'ON CONFLICT(id) DO UPDATE SET enabled = excluded.enabled',
      [if (enabled) 1 else 0],
    );
  }

  Future<DateTime?> lastCheckedAt() async {
    final row = await _row();
    final raw = row?['last_checked_at'] as String?;
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<void> markCheckedNow() async {
    final db = (await _dbFuture).db;
    await db.rawInsert(
      'INSERT INTO sms_detection_settings (id, last_checked_at) '
      'VALUES (1, ?) '
      'ON CONFLICT(id) DO UPDATE SET last_checked_at = excluded.last_checked_at',
      [DateTime.now().toIso8601String()],
    );
  }

  Future<Map<String, Object?>?> _row() async {
    final db = (await _dbFuture).db;
    final rows = await db.query(
      'sms_detection_settings',
      where: 'id = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}
