import 'dart:convert';
import '../../core/constants.dart';

/// Citizen Hazard Report Representation
class HazardReport {
  final String clientReportId;
  final String? ticketId;
  final String photoPath;
  final String? thumbPath;
  final String photoSha256;
  final HazardClass finalClass;
  final String? modelClass;
  final double? modelConfidence;
  final HazardExtent extent;
  final int severityPrelim;
  final double latitude;
  final double longitude;
  final double gpsAccuracyM;
  final DateTime capturedAt;
  final List<String> qualityFlags;
  final String? note;
  final bool isSynced;
  final int retryCount;
  final DateTime? lastAttemptAt;

  HazardReport({
    required this.clientReportId,
    this.ticketId,
    required this.photoPath,
    this.thumbPath,
    required this.photoSha256,
    required this.finalClass,
    this.modelClass,
    this.modelConfidence,
    required this.extent,
    required this.severityPrelim,
    required this.latitude,
    required this.longitude,
    required this.gpsAccuracyM,
    required this.capturedAt,
    this.qualityFlags = const [],
    this.note,
    this.isSynced = false,
    this.retryCount = 0,
    this.lastAttemptAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'client_report_id': clientReportId,
      'ticket_id': ticketId,
      'photo_path': photoPath,
      'thumb_path': thumbPath,
      'photo_sha256': photoSha256,
      'class_final': finalClass.dbValue,
      'class_model': modelClass,
      'model_confidence': modelConfidence,
      'extent': extent.dbValue,
      'severity_prelim': severityPrelim,
      'latitude': latitude,
      'longitude': longitude,
      'gps_accuracy_m': gpsAccuracyM,
      'captured_at': capturedAt.toIso8601String(),
      'quality_flags': jsonEncode(qualityFlags),
      'note': note,
      'is_synced': isSynced ? 1 : 0,
      'retry_count': retryCount,
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
    };
  }

  factory HazardReport.fromMap(Map<String, dynamic> map) {
    List<String> flags = [];
    if (map['quality_flags'] != null) {
      try {
        final decoded = jsonDecode(map['quality_flags']);
        if (decoded is List) {
          flags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return HazardReport(
      clientReportId: map['client_report_id'],
      ticketId: map['ticket_id'],
      photoPath: map['photo_path'],
      thumbPath: map['thumb_path'],
      photoSha256: map['photo_sha256'],
      finalClass: HazardClass.fromString(map['class_final'] ?? 'pothole'),
      modelClass: map['class_model'],
      modelConfidence: map['model_confidence'] != null ? (map['model_confidence'] as num).toDouble() : null,
      extent: HazardExtent.values.firstWhere(
        (e) => e.dbValue == map['extent'],
        orElse: () => HazardExtent.notSure,
      ),
      severityPrelim: map['severity_prelim'] ?? 50,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      gpsAccuracyM: (map['gps_accuracy_m'] as num).toDouble(),
      capturedAt: DateTime.parse(map['captured_at']),
      qualityFlags: flags,
      note: map['note'],
      isSynced: (map['is_synced'] == 1),
      retryCount: map['retry_count'] ?? 0,
      lastAttemptAt: map['last_attempt_at'] != null ? DateTime.parse(map['last_attempt_at']) : null,
    );
  }
}
