/// CivicSync Localization: English & Hindi Strings
/// Specifications: DESIGN.pdf §3, §6, PRD.pdf FR-C8

class AppStrings {
  final String languageCode;

  AppStrings(this.languageCode);

  bool get isHindi => languageCode == 'hi';

  // App General
  String get appTitle => isHindi ? 'सिविकसिंक (CivicSync)' : 'CivicSync';
  String get tagLine => isHindi ? 'सड़क की समस्या बताएं, सुधार देखें' : 'Report road hazards, track real fixes';
  
  // Welcome & Consent Screen (SECURITY.pdf §5.3, §6.1)
  String get welcomeHeading => isHindi ? 'स्वागत है' : 'Welcome to CivicSync';
  String get welcomeBody => isHindi 
      ? 'सड़क की खराबी या गड्ढे की सिर्फ एक तस्वीर लें। हम जगह और समय अपने आप जोड़ देंगे। आपकी निजता सुरक्षित रखने के लिए चेहरे और वाहन की नंबर प्लेट धुंधली कर दी जाती हैं।'
      : 'Point your camera at a road hazard and take a photo. We automatically record the time and place. To protect privacy, faces and vehicle license plates are blurred on your phone.';
  String get ageDeclaration => isHindi ? 'मेरी आयु 18 वर्ष या उससे अधिक है।' : 'I confirm I am 18 years of age or older.';
  String get agreeAndContinue => isHindi ? 'स्वीकार करें और शुरू करें' : 'Agree and Continue';
  
  // Camera & Capture
  String get capturePrompt => isHindi ? 'गड्ढे या रुकावट की तस्वीर लें' : 'Photograph the hazard safely';
  String get tapToCapture => isHindi ? 'तस्वीर खींचें' : 'Take Photo';
  String get lowGpsWarning => isHindi ? 'जीपीएस संकेत कमजोर है। कृपया पिन सही स्थान पर रखें।' : 'GPS signal is weak. Please nudge the pin to the right spot.';
  
  // Triage & Review Screen (PRD.pdf US-C1, US-C3)
  String get reviewHeading => isHindi ? 'समीक्षा और पुष्टि' : 'Confirm Report';
  String get modelGuessPrompt => isHindi ? 'हमारा अनुमान:' : 'Our guess:';
  String get changeClassPrompt => isHindi ? 'यदि गलत है, तो सही प्रकार चुनें:' : 'Tap to change category:';
  String get sizePrompt => isHindi ? 'आकार चुनें:' : 'Select size:';
  String get noteHint => isHindi ? 'अतिरिक्त जानकारी (वैकल्पिक, 200 अक्षर तक)' : 'Add a quick note (optional, up to 200 chars)';
  String get sendButton => isHindi ? 'भेजें (Send)' : 'Send Report';
  String get sending => isHindi ? 'भेजा जा रहा है...' : 'Sending...';
  String get offlineSavedMessage => isHindi 
      ? 'नेटवर्क नहीं है। आपकी रिपोर्ट सुरक्षित सेव कर ली गई है और ऑनलाइन आने पर अपने आप भेज दी जाएगी।'
      : 'Offline. Your report is saved locally and will send automatically when connected.';
  String get thanksMessage => isHindi ? 'धन्यवाद! आपकी रिपोर्ट दर्ज हो गई है।' : 'Thanks! We have received your report.';

  // Categories
  String get classPothole => isHindi ? 'गड्ढा (Pothole)' : 'Pothole';
  String get classOpenDrain => isHindi ? 'खुला नाला या ढक्कन गायब' : 'Open drain / missing cover';
  String get classBrokenRoad => isHindi ? 'टूटी सड़क (Broken road)' : 'Broken / cracked road';
  String get classWaterlogging => isHindi ? 'जलभराव (Waterlogging)' : 'Waterlogging';
  String get classOther => isHindi ? 'अन्य सड़क समस्या' : 'Other road hazard';

  // Sizes
  String get sizeSmall => isHindi ? 'छोटा' : 'Small';
  String get sizeMedium => isHindi ? 'मध्यम' : 'Medium';
  String get sizeLarge => isHindi ? 'बड़ा' : 'Large';
  String get sizeNotSure => isHindi ? 'निश्चित नहीं' : 'Not sure';

  // Statuses (Plain language)
  String get statusReceived => isHindi ? 'प्राप्त हुई' : 'Received';
  String get statusChecked => isHindi ? 'जाँच की गई' : 'Checked';
  String get statusAssigned => isHindi ? 'दल नियुक्त' : 'Crew assigned';
  String get statusFixed => isHindi ? 'सुधार किया गया' : 'Fixed';
  String get statusDelayed => isHindi ? 'इस कार्य में सामान्य से अधिक समय लग रहा है।' : 'This is taking longer than hoped. We have asked for an update.';
  String get stillTherePrompt => isHindi ? 'क्या समस्या अभी भी मौजूद है?' : 'Marked as fixed. Is the problem still there?';

  // Navigation
  String get tabReport => isHindi ? 'रिपोर्ट करें' : 'Report';
  String get tabMyReports => isHindi ? 'मेरी रिपोर्ट्स' : 'My Reports';
  String get tabNearby => isHindi ? 'आस-पास के गड्ढे' : 'Nearby Hazards';
}
