import 'dart:convert';
import 'package:http/http.dart' as http;

/// Un point GPX "déjà samplé" toutes les X minutes
class WeatherSamplePoint {
  final DateTime ts;
  final double lat;
  final double lon;

  WeatherSamplePoint({required this.ts, required this.lat, required this.lon});
}

/// Résultat météo pour UN sample
class WeatherSample {
  final int tsMillis;
  final double lat;
  final double lon;

  final double? tempC;
  final double? feelsLikeC;
  final int? humidityPct;
  final double? windKph;
  final double? precipMm;

  final double? heatIndexC; // on conserve (optionnel)
  final double? windChillC; // on conserve (optionnel)

  final String provider; // "open-meteo"

  WeatherSample({
    required this.tsMillis,
    required this.lat,
    required this.lon,
    required this.provider,
    this.tempC,
    this.feelsLikeC,
    this.humidityPct,
    this.windKph,
    this.precipMm,
    this.heatIndexC,
    this.windChillC,
  });

  Map<String, dynamic> toMap() => {
        'ts': tsMillis,
        'lat': lat,
        'lon': lon,
        'temp_c': tempC,
        'feels_like_c': feelsLikeC,
        'humidity_pct': humidityPct,
        'wind_kph': windKph,
        'precip_mm': precipMm,
        'heat_index_c': heatIndexC,
        'wind_chill_c': windChillC,
        'provider': provider,
      };
}

class OpenMeteoArchiveClient {
  /// Open-Meteo archive: on récupère de l'horaire, puis on prend l'heure la plus proche du sample.
  Future<WeatherSample?> fetchForPoint({
    required DateTime ts,
    required double lat,
    required double lon,
  }) async {
    // On interroge une fenêtre courte (jour du ts)
    final date = _yyyyMmDd(ts);
    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': lat.toStringAsFixed(5),
      'longitude': lon.toStringAsFixed(5),
      'start_date': date,
      'end_date': date,
      'hourly':
          'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m',
      'timezone': 'UTC',
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body);
    final hourly = json['hourly'];
    if (hourly is! Map) return null;

    final times = hourly['time'];
    if (times is! List) return null;

    // Cherche l'heure la plus proche (UTC) du sample
    final target = ts.toUtc();
    int bestIdx = -1;
    Duration? bestDiff;

    for (int i = 0; i < times.length; i++) {
      final tStr = times[i];
      if (tStr is! String) continue;
      final dt = DateTime.tryParse(tStr);
      if (dt == null) continue;

      final diff = (dt.difference(target)).abs();
      if (bestDiff == null || diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }

    if (bestIdx < 0) return null;

    double? dAt(String key) {
      final arr = hourly[key];
      if (arr is! List || bestIdx >= arr.length) return null;
      final v = arr[bestIdx];
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    int? iAt(String key) {
      final v = dAt(key);
      return v == null ? null : v.round();
    }

    final temp = dAt('temperature_2m');
    final feels = dAt('apparent_temperature');
    final hum = iAt('relative_humidity_2m');
    final precip = dAt('precipitation');
    final windMs = dAt('wind_speed_10m');

    // wind_speed_10m est souvent en m/s sur Open-Meteo selon config; ici, on convertit en km/h par sécurité si ça ressemble à du m/s.
    // Heuristique simple: si <= 40, très probablement m/s => convert km/h.
    double? windKph;
    if (windMs != null) {
      windKph = (windMs <= 40) ? windMs * 3.6 : windMs;
    }

    // On conserve heat_index_c / wind_chill_c : ici, on ne les calcule pas encore (null).
    return WeatherSample(
      tsMillis: ts.millisecondsSinceEpoch,
      lat: lat,
      lon: lon,
      provider: 'open-meteo',
      tempC: temp,
      feelsLikeC: feels,
      humidityPct: hum,
      windKph: windKph,
      precipMm: precip,
      heatIndexC: null,
      windChillC: null,
    );
  }

  String _yyyyMmDd(DateTime dt) {
    final u = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}';
  }
}
