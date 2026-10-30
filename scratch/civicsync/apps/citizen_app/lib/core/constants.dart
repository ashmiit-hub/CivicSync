/// CivicSync Domain Constants & Rules
/// Specifications: RULES.pdf, PRD.pdf, TRD.pdf

enum HazardClass {
  pothole,
  openDrain,
  brokenRoad,
  waterlogging,
  other;

  String get dbValue {
    switch (this) {
      case HazardClass.pothole:
        return 'pothole';
      case HazardClass.openDrain:
        return 'open_drain';
      case HazardClass.brokenRoad:
        return 'broken_road';
      case HazardClass.waterlogging:
        return 'waterlogging';
      case HazardClass.other:
        return 'other';
    }
  }

  static HazardClass fromString(String value) {
    switch (value) {
      case 'open_drain':
        return HazardClass.openDrain;
      case 'pothole':
        return HazardClass.pothole;
      case 'broken_road':
        return HazardClass.brokenRoad;
      case 'waterlogging':
        return HazardClass.waterlogging;
      default:
        return HazardClass.other;
    }
  }

  double get classWeight {
    switch (this) {
      case HazardClass.openDrain:
        return 1.00;
      case HazardClass.pothole:
        return 0.80;
      case HazardClass.brokenRoad:
        return 0.60;
      case HazardClass.waterlogging:
        return 0.50;
      case HazardClass.other:
        return 0.40;
    }
  }
}

enum HazardExtent {
  small,
  medium,
  large,
  notSure;

  String get dbValue {
    switch (this) {
      case HazardExtent.small:
        return 'small';
      case HazardExtent.medium:
        return 'medium';
      case HazardExtent.large:
        return 'large';
      case HazardExtent.notSure:
        return 'not_sure';
    }
  }

  double get extentFactor {
    switch (this) {
      case HazardExtent.large:
        return 1.00;
      case HazardExtent.medium:
        return 0.60;
      case HazardExtent.small:
        return 0.30;
      case HazardExtent.notSure:
        return 0.50;
    }
  }
}

enum PlainStatus {
  received,
  checked,
  crewAssigned,
  fixed,
  rejected;

  String get displayNameEn {
    switch (this) {
      case PlainStatus.received:
        return 'Received';
      case PlainStatus.checked:
        return 'Checked';
      case PlainStatus.crewAssigned:
        return 'Crew assigned';
      case PlainStatus.fixed:
        return 'Fixed';
      case PlainStatus.rejected:
        return 'Not actionable';
    }
  }

  String get displayNameHi {
    switch (this) {
      case PlainStatus.received:
        return 'प्राप्त हुई';
      case PlainStatus.checked:
        return 'जाँच की गई';
      case PlainStatus.crewAssigned:
        return 'दल नियुक्त';
      case PlainStatus.fixed:
        return 'सुधार किया गया';
      case PlainStatus.rejected:
        return 'अमान्य';
    }
  }
}

class AppConstants {
  // Pilot Cities
  static const List<String> pilotCities = ['Agra', 'Jodhpur'];

  // Scoring Weights (RULES.pdf §1.1)
  static const double wClass = 0.30;
  static const double wExtent = 0.25;
  static const double wConf = 0.15;
  static const double wLocation = 0.30;
  static const double defaultLocationContext = 0.50; // Unknown on-device

  // Performance Targets (TRD.pdf §2)
  static const int targetInferenceMs = 150;
  static const int targetSubmissionSeconds = 3;
  static const int maxPhotoEdge = 1280;
  static const int maxPhotoKb = 300;
  static const int maxNoteChars = 200;

  // Thresholds (RULES.pdf §2, §6)
  static const double gpsGoodMaxMeters = 30.0;
  static const double gpsWeakMaxMeters = 100.0;
  static const double duplicateAutoMergeRadiusMeters = 25.0;
  static const double duplicateCandidateRadiusMeters = 50.0;

  // Preliminary Severity Calculator (RULES.pdf §1.5)
  static int computePreliminarySeverity({
    required HazardClass hazardClass,
    required HazardExtent extent,
    required double confidence,
  }) {
    final c = hazardClass.classWeight;
    final e = extent.extentFactor;
    final k = confidence.clamp(0.0, 1.0);
    final l = defaultLocationContext;

    final rawScore = 100.0 * (wClass * c + wExtent * e + wConf * k + wLocation * l);
    return rawScore.round().clamp(0, 100);
  }
}
