// lib/services/device_limit_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceSession {
  final String deviceId;
  final String? platform;

  /// Best-effort stable identifier for the physical device.
  /// Used to treat reinstall/relogin on the same phone as the same "device" slot.
  final String? hardwareId;

  /// Human-readable name shown in UI, e.g. "Samsung Galaxy S24 Ultra".
  final String? deviceName;

  /// Legacy model field (kept for backward compatibility with older docs).
  final String? model;

  final bool active;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  DeviceSession({
    required this.deviceId,
    required this.active,
    this.platform,
    this.hardwareId,
    this.deviceName,
    this.model,
    this.lastSeen,
    this.createdAt,
  });

  String get displayName {
    final name = (deviceName ?? '').trim();
    if (name.isNotEmpty) return name;
    final m = (model ?? '').trim();
    if (m.isNotEmpty) return m;
    final p = (platform ?? '').trim();
    return p.isNotEmpty ? p : 'Unknown device';
  }

  static DeviceSession fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    DateTime? _ts(dynamic v) => (v is Timestamp) ? v.toDate() : null;
    return DeviceSession(
      deviceId: doc.id,
      active: d['active'] == true,
      platform: d['platform']?.toString(),
      hardwareId: d['hardwareId']?.toString(),
      deviceName: d['deviceName']?.toString(),
      model: d['model']?.toString(),
      lastSeen: _ts(d['lastSeen']),
      createdAt: _ts(d['createdAt']),
    );
  }
}

class DeviceLimitService {
  final FirebaseFirestore _db;
  DeviceLimitService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _devicesRef(String uid) =>
      _db.collection('users').doc(uid).collection('devices');

  /// Registers (or refreshes) this device as active.
  /// `info` should contain keys like: platform, hardwareId, deviceName/model.
  Future<void> registerThisDevice({
    required String uid,
    required String deviceId,
    required Map<String, dynamic> info,
  }) async {
    await _devicesRef(uid).doc(deviceId).set({
      ...info,
      'active': true,
      'lastSeen': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Returns all active devices, sorted client-side by lastSeen/createdAt (desc).
  /// (We sort client-side to avoid Firestore composite index requirements.)
  Future<List<DeviceSession>> getActiveDevices(String uid) async {
    final snap = await _devicesRef(uid).where('active', isEqualTo: true).get();
    final list = snap.docs.map((d) => DeviceSession.fromDoc(d)).toList();

    int rank(DeviceSession s) {
      final t = s.lastSeen ?? s.createdAt;
      if (t == null) return 0;
      return t.millisecondsSinceEpoch;
    }

    list.sort((a, b) => rank(b).compareTo(rank(a)));
    return list;
  }

  /// Convenience: return ONLY the top [max] active devices (latest first).
  Future<List<DeviceSession>> getTopActiveDevices(String uid, {int max = 2}) async {
    final all = await getActiveDevices(uid);
    if (all.length <= max) return all;
    return all.take(max).toList();
  }

  /// If user reinstalls, deviceId changes, but hardwareId may remain similar.
  /// Deactivates any active sessions with the same [hardwareId], except [keepDeviceId] if provided.
  Future<void> deactivateByHardwareId({
    required String uid,
    required String hardwareId,
    String? keepDeviceId,
  }) async {
    final snap = await _devicesRef(uid).where('active', isEqualTo: true).get();
    final batch = _db.batch();

    for (final doc in snap.docs) {
      final data = doc.data();
      final hid = (data['hardwareId'] ?? '').toString();
      if (hid.isNotEmpty && hid == hardwareId && doc.id != keepDeviceId) {
        batch.set(doc.reference, {
          'active': false,
          'deactivatedAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  Future<void> deactivateDevice({
    required String uid,
    required String deviceId,
  }) async {
    await _devicesRef(uid).doc(deviceId).set({
      'active': false,
      'deactivatedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchThisDevice({
    required String uid,
    required String deviceId,
  }) {
    return _devicesRef(uid).doc(deviceId).snapshots();
  }

  Future<void> touchLastSeen({
    required String uid,
    required String deviceId,
  }) async {
    await _devicesRef(uid).doc(deviceId).set({
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
