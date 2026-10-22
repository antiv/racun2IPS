// Pravi IPS QR kodove za demo podatke store screenshot-ova (render_raw.py),
// istim kodom kao aplikacija: generateIpsString + qr paket (nivo M).
//   fvm flutter test marketing/screenshots/qr_svg_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice2ips/models/invoice_data.dart';
import 'package:invoice2ips/utils/ips.dart';
import 'package:qr_flutter/qr_flutter.dart';

String _svgPath(String data) {
  final image = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final n = image.moduleCount;
  final path = StringBuffer();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (image.isDark(y, x)) path.write('M$x ${y}h1v1h-1z');
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $n $n" '
      'shape-rendering="crispEdges"><path fill="#1A1B19" d="$path"/></svg>';
}

void main() {
  test('demo QR kodovi', () {
    final codes = {
      'result': InvoiceData(
        recipientName: 'Elektro Snabdevanje d.o.o.',
        accountNumber: '160000000001234595',
        amount: 4820,
        purpose: 'Račun za električnu energiju',
        referenceNumber: '97921234567890',
      ),
      'share': InvoiceData(
        recipientName: 'JKP Grad Servis',
        accountNumber: '265000000006789037',
        amount: 6312.40,
        purpose: 'Komunalne usluge',
        referenceNumber: '973020260930',
      ),
    };
    final out = {
      for (final e in codes.entries) e.key: _svgPath(generateIpsString(e.value)),
    };
    File('marketing/screenshots/design/qr.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  });
}
