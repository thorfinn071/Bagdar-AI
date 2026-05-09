enum ArCoreDepthVerdict { supported, unsupported, unknown }

class ArCoreDepthWhitelist {
  ArCoreDepthWhitelist._();

  static const Set<String> _knownSupportedModels = {
    'Pixel 4',
    'Pixel 4 XL',
    'Pixel 4a',
    'Pixel 4a (5G)',
    'Pixel 5',
    'Pixel 5a',
    'Pixel 5a (5G)',
    'Pixel 6',
    'Pixel 6 Pro',
    'Pixel 6a',
    'Pixel 7',
    'Pixel 7 Pro',
    'Pixel 7a',
    'Pixel 8',
    'Pixel 8 Pro',
    'Pixel 8a',
    'Pixel 9',
    'Pixel 9 Pro',
    'Pixel 9 Pro XL',
    'Pixel Fold',
  };

  // Устройства, на которых ARCore depth API заявляет поддержку
  // (`isSupported() == true`), но native libarcore_c.so крашится через
  // 25–60 секунд работы (SIGSEGV в MTC_vio thread).
  // Field-проверено через adb logcat tombstone.
  static const Set<String> _knownUnsupportedModels = {
    'BRP-NX1', // Honor X8b/X9b — ARCore VIO native crash @ ~25s
    'BRP_NX1',
  };

  static const Set<String> _knownUnsupportedBrands = {
    'ITEL',
    'INFINIX',
    'TECNO',
  };

  static const int _minSdkInt = 28;

  static ArCoreDepthVerdict verdict({
    required String manufacturer,
    required String model,
    required String brand,
    required int sdkInt,
  }) {
    if (sdkInt > 0 && sdkInt < _minSdkInt) {
      return ArCoreDepthVerdict.unsupported;
    }
    final brandUpper = brand.toUpperCase();
    if (_knownUnsupportedBrands.contains(brandUpper)) {
      return ArCoreDepthVerdict.unsupported;
    }
    final trimmedModel = model.trim();
    if (_knownUnsupportedModels.contains(trimmedModel)) {
      return ArCoreDepthVerdict.unsupported;
    }
    if (_knownSupportedModels.contains(trimmedModel)) {
      return ArCoreDepthVerdict.supported;
    }
    final manufacturerUpper = manufacturer.toUpperCase();
    if (manufacturerUpper == 'GOOGLE' && trimmedModel.startsWith('Pixel ')) {
      final suffix = trimmedModel.substring(6);
      if (suffix.isNotEmpty && _generationFromModelSuffix(suffix) >= 4) {
        return ArCoreDepthVerdict.supported;
      }
    }
    return ArCoreDepthVerdict.unknown;
  }

  static int _generationFromModelSuffix(String suffix) {
    final match = RegExp(r'^(\d+)').firstMatch(suffix);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }
}
