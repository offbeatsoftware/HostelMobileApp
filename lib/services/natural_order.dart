/// Compares texts the way people expect numbers to sort: "2" before "10",
/// "101" before "101A", ignoring capitals (the desktop NaturalComparer).
int naturalCompare(String x, String y) {
  bool isDigit(int c) => c >= 48 && c <= 57;
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i), cy = y.codeUnitAt(j);
    if (isDigit(cx) && isDigit(cy)) {
      final startX = i, startY = j;
      while (i < x.length && isDigit(x.codeUnitAt(i))) {
        i++;
      }
      while (j < y.length && isDigit(y.codeUnitAt(j))) {
        j++;
      }
      final numberX = x.substring(startX, i).replaceFirst(RegExp('^0+'), '');
      final numberY = y.substring(startY, j).replaceFirst(RegExp('^0+'), '');
      final result = numberX.length != numberY.length
          ? numberX.length.compareTo(numberY.length)
          : numberX.compareTo(numberY);
      if (result != 0) return result;
    } else {
      final result = x[i].toUpperCase().compareTo(y[j].toUpperCase());
      if (result != 0) return result;
      i++;
      j++;
    }
  }
  return (x.length - i).compareTo(y.length - j);
}
