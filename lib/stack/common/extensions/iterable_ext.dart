extension IterableExt<E> on Iterable<E> {
  Map<T, List<E>> groupBy<T>(T Function(E) key) {
    final map = <T, List<E>>{};
    for (final element in this) {
      (map[key(element)] ??= []).add(element);
    }
    return map;
  }

  List<E> sortByNullable<T extends Comparable<T>>(
    T? Function(E) key, {
    bool descending = false,
    bool nullsFirst = false,
  }) {
    final sorted = List<E>.from(this);
    sorted.sort((a, b) {
      final aKey = key(a);
      final bKey = key(b);

      if (aKey == null && bKey == null) {
        return 0;
      }
      if (aKey == null) {
        return nullsFirst ? -1 : 1;
      }
      if (bKey == null) {
        return nullsFirst ? 1 : -1;
      }

      final comparison = aKey.compareTo(bKey);
      return descending ? -comparison : comparison;
    });
    return sorted;
  }
}
