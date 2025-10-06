extension StringExt on String? {
  bool isNullOrEmpty() => this == null || this!.trim().isEmpty;

  String capitalize() {
    if (this == null || this!.isEmpty) return this ?? '';
    return '${this?[0].toUpperCase()}${this?.substring(1).toLowerCase()}';
  }

  String getFirstLetters() {
    if (this == null || this!.isEmpty) return '';
    return this!.split(' ').map((e) => '${e[0]}.').join().toLowerCase();
  }
}
