/// Lightweight LatLng model for representing geospatial coordinates.
///
/// Used by the AOI (Area of Interest) drawing system to store
/// farm boundary points captured from the interactive map.
// A custom model is needed because google_maps_flutter's gmaps.LatLng
// is a platform plugin type that cannot be used freely outside the map widget.
// This app-owned model is aliased as `app.LatLng` in project_screen.dart
// to avoid naming conflicts with gmaps.LatLng.
class LatLng {
  // WGS84 latitude in decimal degrees (-90 to +90)
  final double latitude;

  // WGS84 longitude in decimal degrees (-180 to +180)
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  // Formats as "[lat, lng]" — matches the boundary string format sent to the backend
  // in the System Context block prepended to the analysis message
  @override
  String toString() => '[$latitude, $longitude]';

  // Value equality — two LatLng instances are equal if both coordinates match exactly
  // Needed so Riverpod state comparisons work correctly when the AOI points list changes
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  // Hash code derived from both coordinates — consistent with the == override
  // Required whenever == is overridden so the object works correctly in Sets and Maps
  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}