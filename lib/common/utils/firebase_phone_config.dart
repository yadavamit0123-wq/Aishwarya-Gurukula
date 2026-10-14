import 'package:firebase_core/firebase_core.dart';
import 'package:webinar/common/data/api_public_data.dart';

/// Reads `data.firebase_phone_login` from GET /config.
class FirebasePhoneConfig {
  static Map<String, dynamic>? get _block {
    final data = PublicData.apiConfigData;
    if (data == null) return null;
    final raw = data['firebase_phone_login'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static bool get isEnabled => _block?['enabled'] == true;

  static int get mobileOtpLength {
    final len = _block?['mobile_otp_length'];
    if (len is int) return len;
    return int.tryParse('$len') ?? (isEnabled ? 6 : 5);
  }

  static String get mobileVerificationMethod =>
      _block?['mobile_verification_method']?.toString() ?? (isEnabled ? 'firebase' : 'sms');

  static bool get useFirebasePhoneAuth =>
      isEnabled && mobileVerificationMethod == 'firebase';

  /// Optional web-style Firebase fields from config (mobile uses google-services / plist).
  static FirebaseOptions? get optionsFromConfig {
    final b = _block;
    if (b == null) return null;
    final apiKey = b['api_key']?.toString();
    final appId = b['app_id']?.toString();
    final projectId = b['project_id']?.toString();
    final messagingSenderId = b['messaging_sender_id']?.toString();
    if (apiKey == null || appId == null || projectId == null) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId ?? '',
    );
  }
}
