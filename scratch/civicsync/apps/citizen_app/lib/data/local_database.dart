import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models/report_model.dart';
import '../core/constants.dart';

/// Offline Report Queue Manager (Drift/SQLite interface)
/// Specification: TRD.pdf §3 (TRD-O1 to TRD-O7)
class LocalQueueManager {
  static final LocalQueueManager _instance = LocalQueueManager._internal();
  factory LocalQueueManager() => _instance;
  LocalQueueManager._internal();

  final List<HazardReport> _inMemoryQueue = [];

  List<HazardReport> get inMemoryQueue => List.unmodifiable(_inMemoryQueue);

  /// Enqueue a newly captured report locally
  Future<void> enqueueReport(HazardReport report) async {
    // Check local storage limits (max 200 items, TRD-O2)
    if (_inMemoryQueue.length >= 200) {
      _inMemoryQueue.removeLast(); // Prune oldest
    }
    _inMemoryQueue.insert(0, report);
    debugPrint('Queued report ${report.clientReportId} locally (queue size: ${_inMemoryQueue.length})');
  }

  /// Get pending unsynced reports eligible for retry
  Future<List<HazardReport>> getPendingReports() async {
    final now = DateTime.now();
    return _inMemoryQueue.where((r) {
      if (r.isSynced) return false;
      // Stale check: discard after 7 days (TRD-O2)
      if (now.difference(r.capturedAt).inDays > 7) return false;

      // Exponential backoff interval check: 30s, 2m, 10m, 1h, daily (TRD-O4)
      if (r.lastAttemptAt == null) return true;
      final diff = now.difference(r.lastAttemptAt!);
      switch (r.retryCount) {
        case 0:
          return diff.inSeconds >= 30;
        case 1:
          return diff.inMinutes >= 2;
        case 2:
          return diff.inMinutes >= 10;
        case 3:
          return diff.inHours >= 1;
        default:
          return diff.inDays >= 1;
      }
    }).toList();
  }

  /// Mark report as successfully sent to cloud
  Future<void> markAsSynced(String clientReportId, String ticketId) async {
    final idx = _inMemoryQueue.indexWhere((r) => r.clientReportId == clientReportId);
    if (idx != -1) {
      final old = _inMemoryQueue[idx];
      _inMemoryQueue[idx] = HazardReport(
        clientReportId: old.clientReportId,
        ticketId: ticketId,
        photoPath: old.photoPath,
        thumbPath: old.thumbPath,
        photoSha256: old.photoSha256,
        finalClass: old.finalClass,
        modelClass: old.modelClass,
        modelConfidence: old.modelConfidence,
        extent: old.extent,
        severityPrelim: old.severityPrelim,
        latitude: old.latitude,
        longitude: old.longitude,
        gpsAccuracyM: old.gpsAccuracyM,
        capturedAt: old.capturedAt,
        qualityFlags: old.qualityFlags,
        note: old.note,
        isSynced: true,
        retryCount: old.retryCount,
        lastAttemptAt: DateTime.now(),
      );
    }
  }

  /// Increment retry counter and update timestamp upon failed sync
  Future<void> recordFailedAttempt(String clientReportId) async {
    final idx = _inMemoryQueue.indexWhere((r) => r.clientReportId == clientReportId);
    if (idx != -1) {
      final old = _inMemoryQueue[idx];
      _inMemoryQueue[idx] = HazardReport(
        clientReportId: old.clientReportId,
        ticketId: old.ticketId,
        photoPath: old.photoPath,
        thumbPath: old.thumbPath,
        photoSha256: old.photoSha256,
        finalClass: old.finalClass,
        modelClass: old.modelClass,
        modelConfidence: old.modelConfidence,
        extent: old.extent,
        severityPrelim: old.severityPrelim,
        latitude: old.latitude,
        longitude: old.longitude,
        gpsAccuracyM: old.gpsAccuracyM,
        capturedAt: old.capturedAt,
        qualityFlags: old.qualityFlags,
        note: old.note,
        isSynced: false,
        retryCount: old.retryCount + 1,
        lastAttemptAt: DateTime.now(),
      );
    }
  }

  /// Prune reports older than 7 days
  Future<void> pruneExpired() async {
    final threshold = DateTime.now().subtract(const Duration(days: 7));
    _inMemoryQueue.removeWhere((r) => !r.isSynced && r.capturedAt.isBefore(threshold));
  }
}
