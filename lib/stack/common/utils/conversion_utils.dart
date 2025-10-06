import 'dart:math';

class ConversionUtils {
  static String getFileSizeString({required int bytes, int decimals = 0}) {
    if (bytes <= 0) return '0 Bytes';
    const suffixes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1000)).floor();
    if (i == 0) {
      return '$bytes ${suffixes[i]}';
    } else if (i == 1) {
      return '${(bytes / pow(1000, i)).round()} ${suffixes[i]}';
    } else {
      return '${(bytes / pow(1000, i)).toStringAsFixed(1)} ${suffixes[i]}';
    }
  }
}
