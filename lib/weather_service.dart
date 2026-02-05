import 'package:hive_flutter/hive_flutter.dart';

import 'weather_auto_open_meteo.dart';
import 'weather_gpx_tools.dart';

class WeatherService {
  WeatherService({
    OpenMeteoArchiveClient? client,
    Box? activitiesBox,
    Box? cacheBox,
  })  : _client = client ?? OpenMeteoArchiveClient(),
        _activities = activitiesBox ?? Hive.box('activities'),
        _cache = cacheBox ?? Hive.box('weather_cache');

  final OpenMeteoArchiveClient _client;
  final Box _activities;
  final Box _cache;

  String _cacheKey(GpxPoint p) => '${p.ts}_${p.lat}_${p.lon}';

  Future<void> computeAndAttachWeather({
    required dynamic activityKey,
    required List<GpxPoint> gpxSamples10m,
    void Function(int done, int total)? onProgress,
  }) async {
    final total = gpxSamples10m.length;
    int done = 0;

    final weatherSamples = <Map<String, dynamic>>[];

    for (final p in gpxSamples10m) {
      final key = _cacheKey(p);

      Map<String, dynamic>? map;

      final cached = _cache.get(key);
      if (cached is Map) {
        map = Map<String, dynamic>.from(cached);
      } else {
        final w = await _client.fetchForPoint(
          ts: DateTime.fromMillisecondsSinceEpoch(p.ts, isUtc: true),
          lat: p.lat,
          lon: p.lon,
        );
        if (w != null) {
          map = w.toMap();
          await _cache.put(key, map);
        }
      }

      if (map != null) weatherSamples.add(map);

      done += 1;
      onProgress?.call(done, total);
    }

    double? avgD(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

    int? avgI(List<int> xs) =>
        xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length).round();

    List<double> takeD(String k) => weatherSamples
        .map((m) => m[k])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();

    List<int> takeI(String k) => weatherSamples
        .map((m) => m[k])
        .whereType<num>()
        .map((v) => v.toInt())
        .toList();

    final temps = takeD('temp_c');
    final feels = takeD('feels_like_c');
    final winds = takeD('wind_kph');
    final precs = takeD('precip_mm');
    final hums = takeI('humidity_pct');

    // on repart de ce qui est stocké
    final stored = _activities.get(activityKey);
    if (stored is! Map) return;

    final updated = Map<String, dynamic>.from(stored);
    updated['weather_samples_10m'] = weatherSamples;
    updated['weather'] = <String, dynamic>{
      'temp_c': avgD(temps),
      'feels_like_c': avgD(feels),
      'humidity_pct': avgI(hums),
      'wind_kph': avgD(winds),
      'precip_mm': avgD(precs),
      'heat_index_c': null,
      'wind_chill_c': null,
      'provider': 'open-meteo',
    };
    updated['weather_status'] = 'ok';

    await _activities.put(activityKey, updated);
  }
}
