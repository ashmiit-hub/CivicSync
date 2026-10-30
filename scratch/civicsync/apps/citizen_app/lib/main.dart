import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'core/constants.dart';
import 'core/localization.dart';
import 'data/models/report_model.dart';
import 'services/location_service.dart';
import 'services/inference_service.dart';
import 'services/privacy_blur_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CivicSyncCitizenApp());
}

class CivicSyncCitizenApp extends StatefulWidget {
  const CivicSyncCitizenApp({super.key});

  @override
  State<CivicSyncCitizenApp> createState() => _CivicSyncCitizenAppState();
}

class _CivicSyncCitizenAppState extends State<CivicSyncCitizenApp> {
  String _locale = 'en';

  void _toggleLocale() {
    setState(() {
      _locale = _locale == 'en' ? 'hi' : 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(_locale);

    return MaterialApp(
      title: 'CivicSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5), // Civic Trust Blue
          primary: const Color(0xFF1565C0),
          secondary: const Color(0xFFFF9800), // Action Amber
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: HomeScreen(
        strings: strings,
        onToggleLocale: _toggleLocale,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final AppStrings strings;
  final VoidCallback onToggleLocale;

  const HomeScreen({
    super.key,
    required this.strings,
    required this.onToggleLocale,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<HazardReport> _submittedReports = [];

  void _addReport(HazardReport report) {
    setState(() {
      _submittedReports.insert(0, report);
      _currentIndex = 1; // Switch to "My Reports" tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: widget.onToggleLocale,
            icon: const Icon(Icons.language, color: Colors.white),
            label: Text(
              strings.isHindi ? 'English' : 'हिंदी',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CaptureFlowView(
            strings: strings,
            onReportSubmitted: _addReport,
          ),
          MyReportsView(
            strings: strings,
            reports: _submittedReports,
          ),
          NearbyHazardsView(strings: strings),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.camera_alt_outlined),
            selectedIcon: const Icon(Icons.camera_alt),
            label: strings.tabReport,
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: strings.tabMyReports,
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: strings.tabNearby,
          ),
        ],
      ),
    );
  }
}

/// Screen 1: Instant Camera & Fast Triage Flow (<30s target)
class CaptureFlowView extends StatefulWidget {
  final AppStrings strings;
  final ValueChanged<HazardReport> onReportSubmitted;

  const CaptureFlowView({
    super.key,
    required this.strings,
    required this.onReportSubmitted,
  });

  @override
  State<CaptureFlowView> createState() => _CaptureFlowViewState();
}

class _CaptureFlowViewState extends State<CaptureFlowView> {
  bool _isCaptured = false;
  bool _isProcessing = false;
  HazardClass _selectedClass = HazardClass.pothole;
  HazardExtent _selectedExtent = HazardExtent.medium;
  final TextEditingController _noteController = TextEditingController();
  
  LocationReading? _location;
  InferenceResult? _inference;
  BlurResult? _blurResult;

  Future<void> _handleCapture() async {
    setState(() => _isProcessing = true);

    // 1. Get GPS with accuracy verification
    final loc = await LocationService.getCurrentReading();

    // 2. Mock camera capture & privacy blur
    final dummyFile = File('pothole_sample.jpg');
    final blur = await PrivacyBlurService.processPhoto(dummyFile);

    // 3. Run on-device TFLite inference
    final inferenceSvc = HazardInferenceService();
    await inferenceSvc.initialize();
    final inf = await inferenceSvc.classifyImage(dummyFile);

    setState(() {
      _location = loc;
      _blurResult = blur;
      _inference = inf;
      if (inf.suggestedClass != null) {
        _selectedClass = inf.suggestedClass!;
      }
      _isCaptured = true;
      _isProcessing = false;
    });
  }

  void _handleSubmit() {
    if (_location == null || _blurResult == null) return;

    final prelimSeverity = AppConstants.computePreliminarySeverity(
      hazardClass: _selectedClass,
      extent: _selectedExtent,
      confidence: _inference?.confidence ?? 0.8,
    );

    final report = HazardReport(
      clientReportId: const Uuid().v4(),
      photoPath: 'reports/local/img_${DateTime.now().millisecondsSinceEpoch}.webp',
      photoSha256: _blurResult!.sha256Hash,
      finalClass: _selectedClass,
      modelClass: _inference?.rawLabel,
      modelConfidence: _inference?.confidence,
      extent: _selectedExtent,
      severityPrelim: prelimSeverity,
      latitude: _location!.latitude,
      longitude: _location!.longitude,
      gpsAccuracyM: _location!.accuracyMeters,
      capturedAt: DateTime.now(),
      qualityFlags: [
        if (_location!.isLowAccuracy) 'low_gps',
        if (_location!.isMocked) 'mock_location',
        if (_blurResult!.blurFailed) 'privacy_blur_failed',
      ],
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      isSynced: true,
    );

    widget.onReportSubmitted(report);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.strings.thanksMessage),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 3),
      ),
    );

    // Reset capture
    setState(() {
      _isCaptured = false;
      _location = null;
      _blurResult = null;
      _inference = null;
      _noteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;

    if (_isProcessing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing photo & location on device...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    if (!_isCaptured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: 90,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                s.capturePrompt,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                s.welcomeBody,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                onPressed: _handleCapture,
                icon: const Icon(Icons.camera_enhance, size: 28),
                label: Text(s.tapToCapture, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Triage & Confirm Screen
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Simulated Captured Image Container
          Stack(
            children: [
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(16),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/sample_pothole.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.image, size: 80, color: Colors.grey[600]),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Privacy blur applied',
                        style: TextStyle(color: Colors.grey[200], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Location Banner with Low GPS nudge warning if needed
          if (_location != null)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      _location!.isLowAccuracy ? Icons.warning_amber_rounded : Icons.location_on,
                      color: _location!.isLowAccuracy ? Colors.amber[800] : Colors.green[700],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agra / Jodhpur Pilot Ward (GPS ±${_location!.accuracyMeters.toStringAsFixed(1)}m)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          if (_location!.isLowAccuracy)
                            Text(
                              s.lowGpsWarning,
                              style: TextStyle(color: Colors.amber[900], fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // On-device AI Suggestion banner (RULES.pdf §8.1)
          if (_inference != null && _inference!.isConfidentGuess)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '${s.modelGuessPrompt} ${_formatClass(_selectedClass, s)} (${(_inference!.confidence * 100).toInt()}%)',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blue),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Category Selector Chips
          Text(s.changeClassPrompt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: HazardClass.values.map((cls) {
              final isSelected = _selectedClass == cls;
              return ChoiceChip(
                label: Text(_formatClass(cls, s)),
                selected: isSelected,
                onSelected: (val) {
                  if (val) setState(() => _selectedClass = cls);
                },
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Size Extent Chips
          Text(s.sizePrompt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: HazardExtent.values.map((ext) {
              final isSelected = _selectedExtent == ext;
              return ChoiceChip(
                label: Text(_formatExtent(ext, s)),
                selected: isSelected,
                onSelected: (val) {
                  if (val) setState(() => _selectedExtent = ext);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Optional Note Field
          TextField(
            controller: _noteController,
            maxLength: AppConstants.maxNoteChars,
            decoration: InputDecoration(
              hintText: s.noteHint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          // Submit Button
          ElevatedButton.icon(
            onPressed: _handleSubmit,
            icon: const Icon(Icons.send),
            label: Text(s.sendButton, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _isCaptured = false),
            child: const Text('Retake Photo'),
          ),
        ],
      ),
    );
  }

  String _formatClass(HazardClass cls, AppStrings s) {
    switch (cls) {
      case HazardClass.pothole:
        return s.classPothole;
      case HazardClass.openDrain:
        return s.classOpenDrain;
      case HazardClass.brokenRoad:
        return s.classBrokenRoad;
      case HazardClass.waterlogging:
        return s.classWaterlogging;
      case HazardClass.other:
        return s.classOther;
    }
  }

  String _formatExtent(HazardExtent ext, AppStrings s) {
    switch (ext) {
      case HazardExtent.small:
        return s.sizeSmall;
      case HazardExtent.medium:
        return s.sizeMedium;
      case HazardExtent.large:
        return s.sizeLarge;
      case HazardExtent.notSure:
        return s.sizeNotSure;
    }
  }
}

/// Screen 2: "My Reports" with Transparent Plain-Language Statuses
class MyReportsView extends StatelessWidget {
  final AppStrings strings;
  final List<HazardReport> reports;

  const MyReportsView({
    super.key,
    required this.strings,
    required this.reports,
  });

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 70, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No reports submitted yet.',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (ctx, idx) {
        final r = reports[idx];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      r.finalClass.name.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    _buildStatusChip(PlainStatus.received),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Captured: ${r.capturedAt.toLocal().toString().split('.')[0]}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                Text(
                  'GPS: ${r.latitude.toStringAsFixed(4)}, ${r.longitude.toStringAsFixed(4)} (±${r.gpsAccuracyM.toStringAsFixed(0)}m)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                if (r.note != null) ...[
                  const SizedBox(height: 6),
                  Text('Note: ${r.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
                const Divider(height: 24),
                // Plain Language 4-step progress bar
                Row(
                  children: [
                    _buildStep(strings.statusReceived, true),
                    _buildStep(strings.statusChecked, false),
                    _buildStep(strings.statusAssigned, false),
                    _buildStep(strings.statusFixed, false),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(PlainStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayNameEn,
        style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildStep(String title, bool active) {
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: active ? Colors.blue[700] : Colors.grey[300],
            child: Icon(
              active ? Icons.check : Icons.circle,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? Colors.blue[900] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Screen 3: Privacy-Preserving Nearby Open Hazards View
class NearbyHazardsView extends StatelessWidget {
  final AppStrings strings;

  const NearbyHazardsView({super.key, required this.strings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_city, size: 80, color: Colors.blue[300]),
            const SizedBox(height: 16),
            const Text(
              'Nearby Open Hazards',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Showing reported hazards within 500m in Agra / Jodhpur without photos or identities.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
