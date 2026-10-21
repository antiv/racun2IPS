/// Srpski format iznosa: tačka za hiljade, zarez za decimale (4.820,00).
String formatAmount(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '$whole,${parts[1]}';
}
