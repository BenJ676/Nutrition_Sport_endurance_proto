import 'dart:io';
import 'package:xml/xml.dart';

class GpxPoint {
  final double lat;
  final double lon;
  final DateTime time;

  const GpxPoint({required this.lat, required this.lon, required this.time});

  @override
  String toString() => 'GpxPoint(lat:$lat, lon:$lon, time:$time)';
}

class WeatherGpxTools {
  /// Parse a GPX file content and returns all track points (trkpt) that have time.
  static List<GpxPoint> parseGpx(String gpxXml) {
    final doc = XmlDocument.parse(gpxXml);

    final points = <GpxPoint>[];

    final trkpts = doc.findAllElements('trkpt');
    for (final p in trkpts) {
      final latStr = p.getAttribute('lat');
      final lonStr = p.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;

      final timeEl = p.getElement('time');
      if (timeEl == null) continue;

      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) continue;

      final time = DateTime.tryParse(timeEl.innerText.trim());
      if (time == null) continue;

      points.add(GpxPoint(lat: lat, lon: lon, time: time.toUtc()));
    }

    // GPX points are usually already ordered, but we sort just in case.
    points.sort((a, b) => a.time.compareTo(b.time));
    return points;
  }

  /// Convenience: load a GPX from file path (desktop/dev use).
  static Future<List<GpxPoint>> loadFromFile(String path) async {
    final content = await File(path).readAsString();
    return parseGpx(content);
  }

  /// Downsample/choose points every [step] (e.g. 10 minutes) using the closest point after each target time.
  static List<GpxPoint> sampleEvery(List<GpxPoint> points, Duration step) {
    if (points.isEmpty) return const [];

    final out = <GpxPoint>[];
    final start = points.first.time;
    final end = points.last.time;

    var target = start;
    var idx = 0;

    while (!target.isAfter(end)) {
      // advance idx until points[idx].time >= target
      while (idx < points.length && points[idx].time.isBefore(target)) {
        idx++;
      }
      if (idx >= points.length) break;

      out.add(points[idx]);
      target = target.add(step);
    }

    // ensure unique times (optional safety)
    final uniq = <int, GpxPoint>{};
    for (final p in out) {
      uniq[p.time.millisecondsSinceEpoch] = p;
    }
    final result = uniq.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}
