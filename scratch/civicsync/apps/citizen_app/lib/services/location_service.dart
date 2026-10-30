import 'package:geolocator/geolocator.dart';
import '../core/constants.dart';

class LocationReading {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final bool isMocked;
  final bool isLowAccuracy;
  final bool isVeryLowAccuracy;

  LocationReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isMocked,
    required this.isLowAccuracy,
    required this.isVeryLowAccuracy,
  });
}

/// Precise Location Service with Quality Assessment
/// Specification: RULES.pdf §2.1 - §2.3, TRD.pdf §7
class LocationService {
  /// Request GPS location and assess accuracy
  static Future<LocationReading> getCurrentReading() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Default to Agra pilot center coordinate with low accuracy flag if disabled
      return LocationReading(
        latitude: 27.1767,
        longitude: 78.0081,
        accuracyMeters: 120.0,
        isMocked: false,
        isLowAccuracy: true,
        isVeryLowAccuracy: true,
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return LocationReading(
        latitude: 27.1767,
        longitude: 78.0081,
        accuracyMeters: 150.0,
        isMocked: false,
        isLowAccuracy: true,
        isVeryLowAccuracy: true,
      );
    }

    // Capture location with 10s timeout (TRD.pdf §7)
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    final acc = position.accuracy;
    return LocationReading(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: acc,
      isMocked: position.isMocked,
      isLowAccuracy: acc > AppConstants.gpsGoodMaxMeters,
      isVeryLowAccuracy: acc > AppConstants.gpsWeakMaxMeters,
    );
  }
}
