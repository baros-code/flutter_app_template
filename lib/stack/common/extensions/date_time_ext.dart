import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

extension DateTimeExt on DateTime {
  String format(String pattern, [BuildContext? context]) {
    return DateFormat(pattern).format(this);
  }

  DateTime simplify() {
    return DateTime(year, month, day);
  }

  String getDefaultTime() => format('HH:mm');

  String formatDefault({
    bool includeTime = false,
    bool commaSeparator = false,
  }) => format(
    includeTime
        ? commaSeparator
              ? 'dd/MM/yyyy, HH:mm'
              : 'dd/MM/yyyy - HH:mm'
        : 'dd/MM/yyyy',
  );

  bool isAtSameMomentAsOrBefore(DateTime other) {
    return isAtSameMomentAs(other) || isBefore(other);
  }

  bool isAtSameMomentAsOrAfter(DateTime other) {
    return isAtSameMomentAs(other) || isAfter(other);
  }

  bool isAtSameDayAs(DateTime other) {
    return day == other.day && month == other.month && year == other.year;
  }

  bool isBeforeDay(DateTime other) {
    return DateTime(
      year,
      month,
      day,
    ).isBefore(DateTime(other.year, other.month, other.day));
  }

  bool isAfterDay(DateTime other) {
    return DateTime(
      year,
      month,
      day,
    ).isAfter(DateTime(other.year, other.month, other.day));
  }

  bool isAtSameDayAsOrBefore(DateTime other) {
    return isAtSameDayAs(other) || isBeforeDay(other);
  }

  bool isAtSameDayAsOrAfter(DateTime other) {
    return isAtSameDayAs(other) || isAfterDay(other);
  }

  int daysBetween(DateTime other) {
    return (difference(other).inHours / 24).round();
  }
}

extension DateTimeNullableExt on DateTime? {
  int compareNullableDate(DateTime? date) {
    if (date == null && this == null) return 0;
    if (date == null) return 1;
    if (this == null) return -1;

    return this!.compareTo(date);
  }
}
