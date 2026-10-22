import 'package:webinar/common/data/api_public_data.dart';

/// Reads `data.ai_assistant` from GET /config (PublicData.apiConfigData).
class AiAssistantConfig {
  static Map<String, dynamic>? get _block {
    final data = PublicData.apiConfigData;
    if (data == null) return null;
    final ai = data['ai_assistant'];
    if (ai is Map<String, dynamic>) return ai;
    if (ai is Map) return Map<String, dynamic>.from(ai);
    return null;
  }

  static bool get isGloballyEnabled => _block?['enabled'] == true;

  static bool get allowTextSearch => _block?['allow_text_search'] != false;

  static bool get allowCourseSearch => _block?['allow_course_search'] == true;

  static bool get allowSubjectSearch => _block?['allow_subject_search'] == true;

  static bool get allowImageGenerate => _block?['allow_image_generate'] == true;

  /// Vision search (screenshot / photo with question).
  static bool get allowImageSearch => _block?['allow_image_search'] != false;

  static bool get hasAnySearchScope =>
      allowTextSearch || allowCourseSearch || allowSubjectSearch;
}
