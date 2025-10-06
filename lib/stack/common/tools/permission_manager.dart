import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

abstract class PermissionManager {
  Future<PermissionResult> checkPermission(
    PermissionType permissionType, {
    FutureOr<void> Function()? onGranted,
  });

  Future<PermissionResult> getPermissionStatus(PermissionType permissionType);

  Future<bool> getPermissionServiceStatus(PermissionType permissionType);

  Future<bool> openAppPermissionSettings();
}

class PermissionManagerImpl implements PermissionManager {
  @override
  Future<PermissionResult> checkPermission(
    PermissionType permissionType, {
    FutureOr<void> Function()? onGranted,
  }) async {
    for (final permission in permissionType._permissions) {
      final result = await _checkPermission(
        permissionType,
        permission,
        onGranted,
      );
      if (result.permissionState.isDenied) {
        return PermissionResult(PermissionState.denied, false);
      } else if (result.permissionState.isPermanentlyDenied) {
        return PermissionResult(
          PermissionState.permanentlyDenied,
          result.firstPermanentlyDenied,
        );
      }
    }
    return PermissionResult(PermissionState.granted, false);
  }

  Future<PermissionResult> _checkPermission(
    PermissionType permissionType,
    Permission permission,
    FutureOr<void> Function()? onGranted,
  ) async {
    if (permissionType.isStorage &&
        (await _isPermissionNotNeededForStorage(permissionType))) {
      return PermissionResult(PermissionState.granted, false);
    }

    var permissionState = PermissionState._getByValue(await permission.status);

    var firstPermanentlyDenied = false;
    permission.onPermanentlyDeniedCallback(() {
      firstPermanentlyDenied = true;
    });

    permission.onGrantedCallback(onGranted);

    if (permissionState._value == PermissionStatus.denied) {
      if (permissionType == PermissionType.notification &&
          await _isPermanentlyDeniedForAndroid12AndLower()) {
        return PermissionResult(PermissionState.permanentlyDenied, false);
      }
      final result = await permission.request();
      permissionState = PermissionState._getByValue(result);
    }

    return PermissionResult(permissionState, firstPermanentlyDenied);
  }

  @override
  Future<bool> openAppPermissionSettings() async {
    return openAppSettings();
  }

  @override
  Future<PermissionResult> getPermissionStatus(
    PermissionType permissionType,
  ) async {
    for (final permission in permissionType._permissions) {
      if (await permission.status == PermissionStatus.denied) {
        return PermissionResult(PermissionState.denied, false);
      } else if (await permission.status ==
          PermissionStatus.permanentlyDenied) {
        return PermissionResult(PermissionState.permanentlyDenied, false);
      }
    }
    return PermissionResult(
      PermissionState._getByValue(PermissionStatus.granted),
      false,
    );
  }

  @override
  Future<bool> getPermissionServiceStatus(PermissionType permissionType) async {
    for (final permission in permissionType._permissions) {
      if (permission is! PermissionWithService) {
        continue;
      }
      if (await permission.serviceStatus != ServiceStatus.enabled) {
        return false;
      }
    }
    return true;
  }

  // Helpers
  Future<bool> _isPermanentlyDeniedForAndroid12AndLower() async {
    if (!Platform.isAndroid) return false;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt < 33;
  }

  Future<bool> _isPermissionNotNeededForStorage(
    PermissionType permissionType,
  ) async {
    if (Platform.isIOS) return true;

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final requiredSdkVersion = permissionType == PermissionType.storageWrite
          ? 28
          : 32;

      if (info.version.sdkInt > requiredSdkVersion) return true;
    }

    return false;
  }

  // - Helpers
}

class PermissionResult {
  PermissionResult(this.permissionState, this.firstPermanentlyDenied);

  final PermissionState permissionState;
  final bool firstPermanentlyDenied;

  bool get isGranted => permissionState == PermissionState.granted;
}

enum PermissionType {
  location([Permission.location]),
  camera([Permission.camera]),
  storageWrite([Permission.storage]),
  storageRead([Permission.storage]),
  notification([Permission.notification]),
  bluetoothAndroid([Permission.bluetoothScan, Permission.bluetoothConnect]),
  bluetoothIOS([Permission.bluetooth]),
  bluetoothService([Permission.bluetooth]);

  const PermissionType(this._permissions);

  final List<Permission> _permissions;

  Future<bool> get isGranted async {
    final result = await Future.wait(
      _permissions.map((e) => e.isGranted).toList(),
    );
    return result.every((isGranted) => isGranted);
  }

  bool get isStorage =>
      this == PermissionType.storageWrite || this == PermissionType.storageRead;

  String get title {
    switch (this) {
      case location:
        return 'Location access permission';
      case camera:
        return 'Camera access permission';
      case storageWrite:
      case storageRead:
        return 'File access permission';
      case notification:
        return 'Notification permission';
      case bluetoothService:
      case bluetoothAndroid:
      case bluetoothIOS:
        return 'Bluetooth permission';
    }
  }

  String get bodyMessageParam {
    switch (this) {
      case location:
        return 'You have to give location permission to use this service';
      case camera:
        return 'You have to give camera permission to use this service';
      case storageWrite:
      case storageRead:
        return 'You have to give storage permission to use this service';
      case notification:
        return 'You have to give notification permission to use this service';
      case bluetoothService:
      case bluetoothAndroid:
      case bluetoothIOS:
        return 'You have to give bluetooth permission to use this service';
    }
  }
}

enum PermissionState {
  granted(PermissionStatus.granted),
  denied(PermissionStatus.denied),
  permanentlyDenied(PermissionStatus.permanentlyDenied);

  const PermissionState(this._value);

  final PermissionStatus _value;

  bool get isGranted => this == granted;

  bool get isDenied => this == denied;

  bool get isPermanentlyDenied => this == permanentlyDenied;

  static PermissionState _getByValue(PermissionStatus status) {
    return PermissionState.values.firstWhere(
      (e) => e._value == status,
      orElse: () => denied,
    );
  }
}
