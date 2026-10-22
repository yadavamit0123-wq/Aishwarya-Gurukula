import 'dart:convert';

import 'package:http/http.dart';
import 'package:webinar/app/models/ai_assistant_model.dart';
import 'package:webinar/app/services/authentication_service/authentication_service.dart';
import 'package:webinar/common/enums/error_enum.dart';
import 'package:webinar/common/utils/constants.dart';
import 'package:webinar/common/utils/error_handler.dart';
import 'package:webinar/common/utils/http_handler.dart';

class AiAssistantService {
  static String? _errorCode(Map<String, dynamic> json) {
    return json['error_code']?.toString() ?? json['code']?.toString();
  }

  static String messageForErrorCode(String? code) {
    switch (code) {
      case 'AI_DISABLED':
        return 'AI assistant is currently unavailable.';
      case 'AI_NOT_ENTITLED':
        return 'Your plan does not include AI assistant. Please upgrade your subscription.';
      case 'FEATURE_NOT_ALLOWED':
        return 'This AI feature is not enabled for your account.';
      case 'QUOTA_EXCEEDED':
        return 'You have used all AI searches for this period.';
      case 'COURSE_NOT_ACCESSIBLE':
        return 'You do not have access to this course.';
      case 'PROVIDER_ERROR':
        return 'AI service is temporarily unavailable. Please try again later.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  static Future<AiAssistantUsage?> getUsage({bool showError = false}) async {
    try {
      final url = '${Constants.baseUrl}panel/ai/usage';
      final res = await httpGetWithToken(url);
      final json = parseCleanJson(res.body.toString());
      if (json['success'] == true && json['data'] != null) {
        return AiAssistantUsage.fromJson(Map<String, dynamic>.from(json['data']));
      }
      if (showError) {
        ErrorHandler().showError(ErrorEnum.error, json, readMessage: true);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<AiAssistantCourseItem>> getCourses() async {
    final list = <AiAssistantCourseItem>[];
    try {
      final url = '${Constants.baseUrl}panel/ai/courses';
      final res = await httpGetWithToken(url);
      final json = parseCleanJson(res.body.toString());
      if (json['success'] == true && json['data'] is List) {
        for (final item in json['data']) {
          if (item is Map) {
            list.add(AiAssistantCourseItem.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (_) {}
    return list;
  }

  static Future<List<AiAssistantSubjectItem>> getSubjects(int courseId) async {
    final list = <AiAssistantSubjectItem>[];
    try {
      final url = '${Constants.baseUrl}panel/ai/courses/$courseId/subjects';
      final res = await httpGetWithToken(url);
      final json = parseCleanJson(res.body.toString());
      if (json['success'] == true && json['data'] is List) {
        for (final item in json['data']) {
          if (item is Map) {
            list.add(AiAssistantSubjectItem.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (_) {}
    return list;
  }

  static Future<({AiAssistantSearchResult? result, String? errorMessage})> search({
    required String query,
    required String scope,
    int? courseId,
    int? subjectId,
    String? conversationId,
    String? imageBase64,
    String? imageMime,
  }) async {
    try {
      final url = '${Constants.baseUrl}panel/ai/search';
      final body = <String, dynamic>{
        'query': query,
        'scope': scope,
        if (courseId != null) 'course_id': courseId,
        if (subjectId != null) 'subject_id': subjectId,
        if (conversationId != null && conversationId.isNotEmpty) 'conversation_id': conversationId,
        if (imageBase64 != null && imageBase64.isNotEmpty) ...{
          'image_base64': imageBase64,
          'image_mime': imageMime ?? 'image/jpeg',
          'image': imageBase64,
        },
      };
      final res = await httpPostWithToken(url, jsonEncode(body));
      final json = parseCleanJson(res.body.toString());
      if (json['success'] == true && json['data'] != null) {
        return (
          result: AiAssistantSearchResult.fromJson(Map<String, dynamic>.from(json['data'])),
          errorMessage: null,
        );
      }
      final code = _errorCode(json);
      final msg = json['message']?.toString() ??
          json['msg']?.toString() ??
          messageForErrorCode(code);
      return (result: null, errorMessage: msg);
    } catch (_) {
      return (result: null, errorMessage: messageForErrorCode(null));
    }
  }

  static Future<({AiAssistantImageResult? result, String? errorMessage})> generateImage({
    required String prompt,
    int? courseId,
  }) async {
    try {
      final url = '${Constants.baseUrl}panel/ai/generate-image';
      final body = <String, dynamic>{
        'prompt': prompt,
        if (courseId != null) 'course_id': courseId,
      };
      final res = await httpPostWithToken(url, jsonEncode(body));
      final json = parseCleanJson(res.body.toString());
      if (json['success'] == true && json['data'] != null) {
        return (
          result: AiAssistantImageResult.fromJson(Map<String, dynamic>.from(json['data'])),
          errorMessage: null,
        );
      }
      final code = _errorCode(json);
      final msg = json['message']?.toString() ??
          json['msg']?.toString() ??
          messageForErrorCode(code);
      return (result: null, errorMessage: msg);
    } catch (_) {
      return (result: null, errorMessage: messageForErrorCode(null));
    }
  }
}
