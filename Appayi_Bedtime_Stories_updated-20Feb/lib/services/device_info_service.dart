// lib/services/device_info_service.dart
//
// Best-effort device metadata builder for Firestore.
// Used by the 2-device login limiter to:
// 1) display a friendly device name in the "choose a device to log out" UI
// 2) generate a best-effort *physical device* signature (hardwareId) so that
//    uninstall/reinstall on the same device can be treated as the same slot.
//
// NOTE: device_info_plus (>=12.x) no longer exposes Android ANDROID_ID, so
// hardwareId on Android is derived from stable-ish build fields. This is not
// guaranteed globally-unique, but works well in practice for "same device" matching.

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DeviceInfoService {
  static final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  /// Returns a map safe to store into Firestore under:
  ///   users/{uid}/devices/{deviceId}
  ///
  /// Common keys:
  ///  - deviceName (String)
  ///  - hardwareId (String)  // best-effort "physical device" signature
  ///  - manufacturer/brand/model/systemName/systemVersion (platform-specific)
  static Future<Map<String, dynamic>> buildFirestoreInfo() async {
    if (kIsWeb) {
      return const {
        'deviceName': 'Web',
        'model': 'Web',
        'hardwareId': 'web',
      };
    }

    try {
      if (Platform.isAndroid) {
        final a = await _plugin.androidInfo;

        final manufacturer = (a.manufacturer).trim();
        final model = (a.model).trim();
        final brand = (a.brand).trim();

        final deviceName = _prettyJoin([
          manufacturer.isNotEmpty ? _capitalize(manufacturer) : null,
          model.isNotEmpty ? model : (brand.isNotEmpty ? _capitalize(brand) : null),
        ]);

        final hardwareId = _stableAndroidHardwareId(a);

        return {
          'deviceName': deviceName.isEmpty ? 'Android device' : deviceName,
          'manufacturer': manufacturer,
          'model': model,
          'brand': brand,
          'sdkInt': a.version.sdkInt,
          if (hardwareId.isNotEmpty) 'hardwareId': hardwareId,
        };
      }

      if (Platform.isIOS) {
        final i = await _plugin.iosInfo;

        final name = (i.name ?? '').trim();
        final model = (i.model ?? '').trim();
        final systemName = (i.systemName ?? '').trim();
        final systemVersion = (i.systemVersion ?? '').trim();

        final deviceName = _prettyJoin([
          name.isNotEmpty ? name : null,
          model.isNotEmpty ? model : null,
        ]);

        final hardwareId = (i.identifierForVendor ?? '').trim();

        return {
          'deviceName': deviceName.isEmpty ? 'iPhone/iPad' : deviceName,
          'model': model,
          'systemName': systemName,
          'systemVersion': systemVersion,
          if (hardwareId.isNotEmpty) 'hardwareId': hardwareId,
        };
      }

      // Other platforms fallback
      return const {
        'deviceName': 'Device',
        'model': 'Device',
      };
    } catch (_) {
      // Never block login due to device info issues.
      return const {
        'deviceName': 'Device',
        'model': 'Device',
      };
    }
  }

  /// Builds a best-effort stable signature for an Android device using build fields.
  /// This is intended for "same physical device" matching across reinstall.
  static String _stableAndroidHardwareId(AndroidDeviceInfo a) {
    // fingerprint is often present and fairly stable per device build.
    // Other fields help differentiate devices.
    final parts = <String>[
      (a.fingerprint).trim(),
      (a.hardware).trim(),
      (a.device).trim(),
      (a.product).trim(),
      (a.model).trim(),
      (a.brand).trim(),
      (a.manufacturer).trim(),
    ];

    // Some versions expose supportedAbis; use it if present & non-empty.
    try {
      final abis = (a.supportedAbis).where((e) => e.trim().isNotEmpty).toList();
      if (abis.isNotEmpty) parts.add(abis.first.trim());
    } catch (_) {
      // ignore
    }

    // Remove empties and join.
    final cleaned = parts.where((p) => p.isNotEmpty).toList();
    if (cleaned.isEmpty) return '';
    return cleaned.join('|');
  }

  static String _prettyJoin(List<String?> parts) {
    return parts
        .where((p) => p != null && p!.trim().isNotEmpty)
        .map((p) => p!.trim())
        .join(' ');
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
