import 'package:webinar/common/data/api_public_data.dart';

/// Reads `data.whatsapp_floating` from GET /config.
class WhatsAppFloatingConfig {
  static Map<String, dynamic>? get _block {
    final data = PublicData.apiConfigData;
    if (data == null) return null;
    final raw = data['whatsapp_floating'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static bool get isEnabled => _block?['enabled'] == true;

  static String get phoneE164 => _block?['phone_e164']?.toString() ?? '';

  static String get waMeUrl => _block?['wa_me_url']?.toString() ?? '';

  static String get defaultMessage => _block?['default_message']?.toString() ?? '';

  static double bottomDp({required bool aiFabVisible}) {
    final hint = _block?['layout_hint'];
    if (hint is Map) {
      if (aiFabVisible) {
        return _asDouble(
          hint['suggested_bottom_dp_when_ai_visible'] ??
              hint['suggested_bottom_dp_with_ai'] ??
              96,
        );
      }
      return _asDouble(
        hint['suggested_bottom_dp'] ??
            hint['suggested_bottom_dp_without_ai'] ??
            24,
      );
    }
    return aiFabVisible ? 96 : 24;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 24;
  }
}
