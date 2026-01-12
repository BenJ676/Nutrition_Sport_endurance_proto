import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenMeteoHourly {
  final List<DateTime> time;
  final List<double?> tempC;
  final List<double?> apparentC;
  final List<double?> humidityPct;
  final List<double?> windKph;
  final List<double?> precipMm;

  OpenMeteoHourly({
    required this.time,
    required this.tempC,
    required this.apparentC,
    required this.humidityPct,
    required this.windKph,
    required this.precipMm,
  });
}

DateTime _parseIso(String s) => DateTime.parse(s).toUtc();

Future<List<dynamic>> fetchOpenMeteoArchiveMulti({
  required List<double> lats,
  required List<double> lons,
  required DateTime startUtc,
  required DateTime endUtc,
}) async {
  final startDate =
      '${startUtc.year.toString().padLeft(4, '0')}-${startUtc.month.toString().padLeft(2, '0')}-${startUtc.day.toString().padLeft(2, '0')}';
  final endDate =
      '${endUtc.year.toString().padLeft(4, '0')}-${endUtc.month.toString().padLeft(2, '0')}-${endUtc.day.toString().padLeft(2, '0')}';

  final latParam = lats.map((e) => e.toStringAsFixed(5)).join(',');
  final lonParam = lons.map((e) => e.toStringAsFixed(5)).join(',');

  final uri =
      Uri.parse('https://archive-api.open-meteo.com/v1/archive').replace(
    queryParameters: {
      'latitude': latParam,
      'longitude': lonParam,
      'start_date': startDate,
      'end_date': endDate,
      'hourly': [
        'temperature_2m',
        'apparent_temperature',
        'relative_humidity_2m',
        'wind_speed_10m',
        'precipitation',
      ].join(','),
      'timezone': 'UTC',
      'wind_speed_unit': 'kmh',
    },
  );

  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('Open-Meteo error ${res.statusCode}: ${res.body}');
  }

  final decoded = jsonDecode(res.body);

  // Selon leur format multi-location, ça peut être un objet ou une liste.
  // On renvoie "toujours une liste de payloads" pour simplifier l’aval.
  if (decoded is List) return decoded;
  if (decoded is Map) return [decoded];
  throw Exception('Open-Meteo: unexpected JSON root');
}

OpenMeteoHourly parseOpenMeteoHourly(Map<String, dynamic> payload) {
  final hourly = (payload['hourly'] as Map).cast<String, dynamic>();

  final time =
      (hourly['time'] as List).map((e) => _parseIso(e.toString())).toList();
  List<double?> toD(String key) => (hourly[key] as List)
      .map((e) => e == null ? null : (e as num).toDouble())
      .toList();

  return OpenMeteoHourly(
    time: time,
    tempC: toD('temperature_2m'),
    apparentC: toD('apparent_temperature'),
    humidityPct: toD('relative_humidity_2m'),
    windKph: toD('wind_speed_10m'),
    precipMm: toD('precipitation'),
  );
}
