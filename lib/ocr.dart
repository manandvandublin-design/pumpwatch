import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReadPrices {
  final double? petrol;
  final double? diesel;
  final String rawText;
  ReadPrices(this.petrol, this.diesel, this.rawText);
}

/// Reads petrol and diesel prices (euro per litre) from a photo of a price sign.
/// Runs entirely on the phone with Google ML Kit, so it needs no internet or API key.
Future<ReadPrices> readPricesFromPhoto(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    final lines = <String>[];
    for (final b in result.blocks) {
      for (final l in b.lines) {
        lines.add(l.text);
      }
    }
    return parsePriceLines(lines);
  } finally {
    await recognizer.close();
  }
}

final _dieselWords = RegExp(r'diesel|dsl|derv|\bd\b', caseSensitive: false);
final _petrolWords = RegExp(r'petrol|unleaded|unl|\b95\b|e10|\bp\b', caseSensitive: false);
// 1.719  1,719  1.71   or cents style 171.9  171,9  171·9
final _priceRe = RegExp(r'(?<!\d)(1[.,·]\d{2,3}|[12]\d{2}[.,·]\d)(?!\d)');

double? _normalise(String s) {
  final t = s.replaceAll(RegExp(r'[,·]'), '.');
  final v = double.tryParse(t);
  if (v == null) return null;
  final euro = v >= 100 ? v / 100.0 : v; // 171.9 cent -> 1.719 euro
  if (euro < 1.0 || euro > 2.9) return null;
  return double.parse(euro.toStringAsFixed(3));
}

/// Works out which number is petrol and which is diesel from the lines of text
/// on a sign. Labels on the same line or the line just before win; otherwise
/// the first price is taken as petrol and the second as diesel, which is the
/// usual order on Irish forecourt signs.
ReadPrices parsePriceLines(List<String> lines) {
  double? petrol;
  double? diesel;
  final unlabelled = <double>[];
  String? lastLabel;

  for (final line in lines) {
    String? label;
    if (_dieselWords.hasMatch(line)) {
      label = 'diesel';
    } else if (_petrolWords.hasMatch(line)) {
      label = 'petrol';
    }
    final matches = _priceRe.allMatches(line).map((m) => _normalise(m.group(1)!)).whereType<double>().toList();
    if (matches.isEmpty) {
      lastLabel = label ?? lastLabel;
      continue;
    }
    final useLabel = label ?? lastLabel;
    for (final v in matches) {
      if (useLabel == 'diesel' && diesel == null) {
        diesel = v;
      } else if (useLabel == 'petrol' && petrol == null) {
        petrol = v;
      } else {
        unlabelled.add(v);
      }
    }
    lastLabel = null;
  }
  for (final v in unlabelled) {
    if (petrol == null) {
      petrol = v;
    } else if (diesel == null) {
      diesel = v;
    }
  }
  return ReadPrices(petrol, diesel, lines.join('\n'));
}
