// lib/services/device_id_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Stable per-install device id.
/// - Generated once and saved locally.
/// - Used for Firestore device session tracking (max devices).
class DeviceIdService {
  static const String _key = 'device_id_v1';
  static const Uuid _uuid = Uuid();

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = _uuid.v4();
    await prefs.setString(_key, id);
    return id;
  }
}
