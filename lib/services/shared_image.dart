import 'package:flutter/services.dart';

/// Kanal ka MainActivity: preuzima sliku podeljenu iz druge aplikacije
/// (Android ACTION_SEND intent). Vraća bajtove slike ili null; native strana
/// briše sliku nakon čitanja, pa se ista slika ne obrađuje dvaput.
const _channel = MethodChannel('rs.antonijevic.invoice2ips/shared');

Future<Uint8List?> getSharedImage() async {
  try {
    return await _channel.invokeMethod<Uint8List>('getSharedImage');
  } on MissingPluginException {
    // iOS / platforme bez implementacije — nema deljenja intentom.
    return null;
  } on PlatformException {
    return null;
  }
}
