import 'package:xml/xml.dart';

class GpxPoint {
  final int ts; // millisecondsSinceEpoch UTC
  final double lat;
  final double lon;

  const GpxPoint({required this.ts, required this.lat, required this.lon});
}

/// Parse GPX -> points (trkpt + time)
List<GpxPoint> parseGpxPoints(String gpxXml) {
  final doc = XmlDocument.parse(gpxXml);

  final pts = <GpxPoint>[];

  for (final trkpt in doc.findAllElements('trkpt')) {
    final latStr = trkpt.getAttribute('lat');
    final lonStr = trkpt.getAttribute('lon');
    if (latStr == null || lonStr == null) continue;

    final lat = double.tryParse(latStr);
    final lon = double.tryParse(lonStr);
    if (lat == null || lon == null) continue;

    final timeEl = trkpt.findElements('time').isNotEmpty
        ? trkpt.findElements('time').first
        : null;
    if (timeEl == null) continue;

    final t = DateTime.tryParse(timeEl.innerText.trim());
    if (t == null) continue;

    pts.add(
      GpxPoint(
        ts: t.toUtc().millisecondsSinceEpoch,
        lat: lat,
        lon: lon,
      ),
    );
  }

  pts.sort((a, b) => a.ts.compareTo(b.ts));
  return pts;
}

/// Keep 1 point every [everyMinutes] minutes (based on timestamps)
List<GpxPoint> sampleEveryMinutes(
  List<GpxPoint> points, {
  int everyMinutes = 10,
}) {
  if (points.isEmpty) return const [];

  final stepMs = everyMinutes * 60 * 1000;
  final out = <GpxPoint>[];

  int nextTs = points.first.ts;
  for (final p in points) {
    if (p.ts >= nextTs) {
      out.add(p);
      nextTs = p.ts + stepMs;
    }
  }
  return out;
}
