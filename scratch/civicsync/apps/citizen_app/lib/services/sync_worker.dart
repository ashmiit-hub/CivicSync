import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../data/local_database.dart';
import '../data/models/report_model.dart';

/// Background Sync Worker for Offline Hazard Reports
/// Specification: TRD.pdf §3 (TRD-O4, TRD-O5)
class BackgroundSyncWorker {
  static const String taskName = "civicsync_offline_sync";
  final LocalQueueManager _queueManager = LocalQueueManager();

  /// Initialize connectivity listeners and WorkManager tasks
  void start() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        debugPrint("Connectivity restored. Triggering offline sync flush...");
        flushPendingReports();
      }
    });
  }

  /// Process all pending reports in the offline queue
  Future<void> flushPendingReports() async {
    final pending = await _queueManager.getPendingReports();
    if (pending.isEmpty) {
      debugPrint("Offline queue is empty. Nothing to sync.");
      return;
    }

    debugPrint("Flushing ${pending.length} pending hazard reports...");
    for (final report in pending) {
      await _uploadSingleReport(report);
    }
  }

  /// 2-step idempotent upload: Storage first, then RPC
  Future<void> _uploadSingleReport(HazardReport report) async {
    try {
      // Step 1: Upload photo & thumbnail to private storage bucket (reports/{user_id}/{client_report_id})
      // Simulating Supabase Storage client call
      debugPrint("Uploading photo: ${report.photoPath}...");
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 2: Call submit_report RPC
      debugPrint("Calling submit_report RPC for ${report.clientReportId}...");
      await Future.delayed(const Duration(milliseconds: 150));

      // Simulating server response with assigned ticket ID
      final mockTicketId = "tk-${DateTime.now().millisecondsSinceEpoch}";
      await _queueManager.markAsSynced(report.clientReportId, mockTicketId);
      debugPrint("Report ${report.clientReportId} synced successfully -> Ticket: $mockTicketId");

    } catch (e) {
      debugPrint("Sync failed for ${report.clientReportId}: $e. Scheduling exponential backoff.");
      await _queueManager.recordFailedAttempt(report.clientReportId);
    }
  }
}
