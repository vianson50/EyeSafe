/// Encodeur G.711 (μ-law et A-law) — portage de la référence publique
/// CCITT/Sun (g711.c), domaine public.
///
/// Utilisé pour le **talk-back** : le micro du téléphone produit du PCM
/// 16 bits 8 kHz mono, la caméra attend du G.711 brut (standard du
/// marché de l'interphonie IP).
library;

class G711 {
  G711._();

  static const List<int> _segUend = [
    0x3F,
    0x7F,
    0xFF,
    0x1FF,
    0x3FF,
    0x7FF,
    0xFFF,
    0x1FFF,
  ];
  static const List<int> _segAend = [
    0x1F,
    0x3F,
    0x7F,
    0xFF,
    0x1FF,
    0x3FF,
    0x7FF,
    0xFFF,
  ];

  static int _search(int val, List<int> table) {
    for (var i = 0; i < table.length; i++) {
      if (val <= table[i]) return i;
    }
    return table.length;
  }

  /// PCM 16 bits signé → octet μ-law (G.711u).
  static int linearToUlaw(int pcm) {
    var v = pcm >> 2;
    int mask;
    if (v < 0) {
      v = -v;
      mask = 0x7F;
    } else {
      mask = 0xFF;
    }
    if (v > 8159) v = 8159;
    v += 0x84 << 1;
    final seg = _search(v, _segUend);
    if (seg >= 8) return 0x7F ^ mask;
    final uval = (seg << 4) | ((v >> (seg + 1)) & 0xF);
    return uval ^ mask;
  }

  /// PCM 16 bits signé → octet A-law (G.711a).
  static int linearToAlaw(int pcm) {
    var v = pcm >> 3;
    int mask;
    if (v >= 0) {
      mask = 0xD5;
    } else {
      mask = 0x55;
      v = -v - 1;
    }
    if (v >= 4096) v = 4095;
    final seg = _search(v, _segAend);
    if (seg >= 8) return 0x7F ^ mask;
    var aval = seg << 4;
    if (seg < 2) {
      aval |= (v >> 1) & 0xF;
    } else {
      aval |= (v >> seg) & 0xF;
    }
    return aval ^ mask;
  }

  /// Encode un tampon PCM 16 bits little-endian (mono) en G.711.
  static List<int> encodePcm16Le(List<int> bytes, {bool aLaw = false}) {
    final sampleCount = bytes.length ~/ 2;
    final out = List<int>.filled(sampleCount, 0);
    for (var i = 0; i < sampleCount; i++) {
      final lo = bytes[i * 2];
      final hi = bytes[i * 2 + 1];
      var sample = (hi << 8) | (lo & 0xFF);
      if (sample >= 0x8000) sample -= 0x10000; // signé
      out[i] = aLaw ? linearToAlaw(sample) : linearToUlaw(sample);
    }
    return out;
  }
}
