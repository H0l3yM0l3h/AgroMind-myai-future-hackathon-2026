/// Lightweight LatLng model for representing geospatial coordinates.
///
/// Used by the AOI (Area of Interest) drawing system to store
/// farm boundary points captured from the interactive map.
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  @override
  String toString() => '[$latitude, $longitude]';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
