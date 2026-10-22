import 'dart:convert';
import 'dart:developer';
import 'package:webinar/app/models/register_config_model.dart';
import 'package:webinar/common/data/app_data.dart';
import 'package:webinar/common/data/api_public_data.dart';
import 'package:webinar/common/utils/firebase_phone_config.dart';
import 'package:webinar/common/enums/error_enum.dart';
import 'package:webinar/common/utils/constants.dart';
import 'package:webinar/common/utils/error_handler.dart';
import 'package:webinar/common/utils/http_handler.dart';
import 'package:http/http.dart';

class AuthLoginResult {
  final bool success;
  final bool needsVerification;
  final Map<String, dynamic>? verification;

  const AuthLoginResult({
    required this.success,
    this.needsVerification = false,
    this.verification,
  });
}

class AuthenticationService {
  static String? _verificationMethodFromResponse(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map) {
      return data['verification_method']?.toString();
    }
    return json['verification_method']?.toString();
  }

  static bool _isMobileAlreadyRegisteredError(Map<String, dynamic> jsonResponse) {
    bool textLooksDuplicate(String? text) {
      if (text == null || text.isEmpty) return false;
      final t = text.toLowerCase();
      final duplicate =
          t.contains('already') || t.contains('taken') || t.contains('exist');
      if (!duplicate) return false;
      return t.contains('mobile') ||
          t.contains('phone') ||
          t.contains('number') ||
          t.contains('username');
    }

    if (textLooksDuplicate(jsonResponse['message']?.toString())) {
      return true;
    }

    final errors = jsonResponse['data']?['errors'];
    if (errors is Map) {
      for (final entry in errors.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key != 'mobile' &&
            key != 'phone' &&
            key != 'username' &&
            !key.contains('mobile')) {
          continue;
        }
        final raw = entry.value;
        final message = raw is List && raw.isNotEmpty
            ? raw.first?.toString()
            : raw?.toString();
        if (textLooksDuplicate(message)) {
          return true;
        }
      }
    }
    return false;
  }

  /// When step-1 rejects a duplicate mobile, still send the user to OTP; show
  /// "already exists" only if verification fails afterward.
  static Map<String, dynamic> _registerPendingOtpPayload() {
    final method = FirebasePhoneConfig.useFirebasePhoneAuth ? 'firebase' : 'sms';
    return {
      'user_id': null,
      'step': 'go_step_2',
      'verification_method': method,
      'deferred_mobile_duplicate_check': true,
    };
  }

  static Map<String, dynamic> _registerStepPayload(Map<String, dynamic> json) {
    final data = json['data'];
    final map = <String, dynamic>{
      'user_id': data is Map ? data['user_id'] : null,
      'step': json['status'],
    };
    final method = _verificationMethodFromResponse(json);
    if (method != null) {
      map['verification_method'] = method;
    }
    return map;
  }
  static Future google(String email, String token, String name) async {
    try {
      String url = '${Constants.baseUrl}google/callback';

      Response res = await httpPost(url, {
        'email': email,
        'name': name,
        'id': token,
      });

      if (res.statusCode == 200) {
        await AppData.saveAccessToken(jsonDecode(res.body)['data']['token']);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future facebook(String email, String token, String name) async {
    try {
      String url = '${Constants.baseUrl}facebook/callback';

      Response res =
          await httpPost(url, {'id': token, 'name': name, 'email': email});

      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success']) {
        await AppData.saveAccessToken(jsonDecode(res.body)['data']['token']);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
// Helper function
  static bool isEmail(String value) {
    return RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(value);
  }

  static Future<AuthLoginResult> login(String username, String password) async {
    try {
      String url = '${Constants.baseUrl}login';
      final normalizedUsername =
          isEmail(username) ? username : (username.startsWith('+') ? username : '+$username');

      Response res = await httpPost(url, {'username': normalizedUsername, 'password': password});

      var jsonResponse = parseCleanJson(res.body.toString());
      log(jsonResponse.toString());

      final data = jsonResponse['data'];
      final token = data is Map ? data['token']?.toString() : null;
      final verificationMethod = _verificationMethodFromResponse(jsonResponse);

      if (jsonResponse['success'] == true && token != null && token.isNotEmpty) {
        await AppData.saveAccessToken(token);
        await AppData.saveName('');
        return const AuthLoginResult(success: true);
      }

      if (verificationMethod != null ||
          jsonResponse['status']?.toString() == 'verification' ||
          (data is Map && data['verification_required'] == true)) {
        final phoneUsername = isEmail(username)
            ? null
            : username.replaceAll('+', '').replaceAll(' ', '');
        return AuthLoginResult(
          success: false,
          needsVerification: true,
          verification: {
            'verification_method': verificationMethod ?? 'sms',
            'username': phoneUsername ?? normalizedUsername.replaceAll('+', ''),
            'countryCode': null,
            'phone': null,
            'password': password,
            'from_login': true,
          },
        );
      }

      ErrorHandler().showError(ErrorEnum.error, jsonResponse, readMessage: true);
      return const AuthLoginResult(success: false);
    } catch (e) {
      return const AuthLoginResult(success: false);
    }
  }

  /// Resend backend SMS OTP (register step 1 or login verification).
  static Future<({bool sent, bool smsLikelyDisabled})> resendPhoneVerification(
    Map<String, dynamic> verifyData,
  ) async {
    if (FirebasePhoneConfig.replacesSmsOtpForMobile) {
      return (sent: false, smsLikelyDisabled: true);
    }

    if (verifyData['from_login'] == true) {
      final password = verifyData['password']?.toString();
      final username = verifyData['username']?.toString();
      if (password == null || username == null || password.isEmpty) {
        return (sent: false, smsLikelyDisabled: false);
      }
      final r = await login(username, password);
      return (sent: r.needsVerification, smsLikelyDisabled: false);
    }

    final phone = verifyData['phone']?.toString();
    final countryCode = verifyData['countryCode']?.toString();
    final password = verifyData['password']?.toString();
    final retype = verifyData['retypePassword']?.toString() ?? password;
    if (phone == null ||
        countryCode == null ||
        password == null ||
        phone.isEmpty ||
        password.isEmpty) {
      return (sent: false, smsLikelyDisabled: false);
    }

    final payload = await registerWithPhone(
      PublicData.apiConfigData?['register_method']?.toString() ?? 'mobile',
      countryCode,
      phone,
      password,
      retype ?? password,
      'user',
      null,
      forceSmsVerification: true,
    );
    return (sent: payload != null, smsLikelyDisabled: false);
  }

  /// POST /verification — mobile Firebase (id_token) or SMS (code).
  static Future<bool> verifyPhoneAccount(String username, {String? code, String? idToken}) async {
    try {
      final url = '${Constants.baseUrl}verification';
      final body = <String, dynamic>{
        'username': username.replaceAll('+', '').replaceAll(' ', ''),
        if (idToken != null && idToken.isNotEmpty) 'id_token': idToken,
        if (code != null && code.isNotEmpty) 'code': code,
      };

      Response res = await httpPost(url, body);
      log(res.body.toString());

      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success'] == true) {
        final token = jsonResponse['data']?['token']?.toString();
        if (token != null && token.isNotEmpty) {
          await AppData.saveAccessToken(token);
        }
        return true;
      } else {
        ErrorHandler().showError(ErrorEnum.error, jsonResponse, readMessage: true);
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Optional passwordless login when admin enables auto-register.
  static Future<bool> firebasePhoneLogin(String idToken, {String? fcmToken}) async {
    try {
      final url = '${Constants.baseUrl}auth/firebase-phone/login';
      Response res = await httpPost(url, {
        'id_token': idToken,
        if (fcmToken != null) 'fcm_token': fcmToken,
      });
      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success'] == true) {
        final token = jsonResponse['data']?['token']?.toString();
        if (token != null && token.isNotEmpty) {
          await AppData.saveAccessToken(token);
          return true;
        }
      }
      ErrorHandler().showError(ErrorEnum.error, jsonResponse, readMessage: true);
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<Map?> registerWithEmail(
      String registerMethod,
      String email,
      String password,
      String repeatPassword,
      String? accountType,
      List<Fields>? fields) async {
    try {
      String url = '${Constants.baseUrl}register/step/1';

      Map body = {
        "register_method": registerMethod,
        "country_code": null,
        'email': email,
        'password': password,
        'password_confirmation': repeatPassword
      };

      if (fields != null) {
        Map bodyFields = {};
        for (var i = 0; i < fields.length; i++) {
          if (fields[i].type != 'upload') {
            bodyFields.addEntries({
              fields[i].id: (fields[i].type == 'toggle')
                  ? fields[i].userSelectedData == null
                      ? 0
                      : 1
                  : fields[i].userSelectedData
            }.entries);
          }
        }

        body.addEntries({'fields': bodyFields.toString()}.entries);
      }
      print(body);

      Response res = await httpPost(url, body);

      var jsonResponse = parseCleanJson(res.body.toString());
      print(jsonResponse);

      if (jsonResponse['success'] ||
          jsonResponse['status'] == 'go_step_2' ||
          jsonResponse['status'] == 'go_step_3') {
        return _registerStepPayload(jsonResponse);
      } else {
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Future<Map?> registerWithPhone(
      String registerMethod,
      String countryCode,
      String mobile,
      String password,
      String repeatPassword,
      String? accountType,
      List<Fields>? fields,
      {bool forceSmsVerification = false}) async {
    try {
      String url = '${Constants.baseUrl}register/step/1';

      Map body = {
        "register_method": registerMethod,
        "country_code": countryCode,
        'mobile': mobile,
        'password': password,
        'password_confirmation': repeatPassword,
        if (forceSmsVerification) ...{
          'verification_method': 'sms',
          'mobile_verification_method': 'sms',
        },
      };
      print(body);

      if (fields != null) {
        Map bodyFields = {};
        for (var i = 0; i < fields.length; i++) {
          if (fields[i].type != 'upload') {
            bodyFields.addEntries({
              fields[i].id: (fields[i].type == 'toggle')
                  ? fields[i].userSelectedData == null
                      ? 0
                      : 1
                  : fields[i].userSelectedData
            }.entries);
          }
        }

        body.addEntries({'fields': bodyFields.toString()}.entries);
      }

      Response res = await httpPost(url, body);

      print(res.body);

      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success'] ||
          jsonResponse['status'] == 'go_step_2' ||
          jsonResponse['status'] == 'go_step_3') {
        // || stored

        final payload = _registerStepPayload(jsonResponse);
        payload['verification_method'] ??=
            _verificationMethodFromResponse(jsonResponse) ?? 'sms';
        return payload;
      } else {
        if (_isMobileAlreadyRegisteredError(jsonResponse)) {
          return _registerPendingOtpPayload();
        }
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Future<bool> forgetPassword(String? countryCode, String data) async {
    try {
      String url = '${Constants.baseUrl}forget-password';

      Response res = await httpPost(url, {
        'type': countryCode == null ? 'email' : 'mobile',
        if (countryCode == null) ...{
          "email": data
        } else ...{
          "country_code": countryCode,
          "mobile": data,
        }
      });

      log(res.body.toString());

      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success']) {
        ErrorHandler()
            .showError(ErrorEnum.success, jsonResponse, readMessage: true);
        return true;
      } else {
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future<bool> verifyCode(int userId, String code) async {
    try {
      String url = '${Constants.baseUrl}register/step/2';

      Response res = await httpPost(url, {
        "user_id": userId.toString(),
        "code": code,
      });

      log(res.body.toString());

      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success']) {
        return true;
      } else {
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future<bool> registerStep3(
      int userId, String name, String referralCode) async {
    try {
      String url = '${Constants.baseUrl}register/step/3';

      Response res = await httpPost(url, {
        "user_id": userId.toString(),
        "full_name": name,
        "referral_code": referralCode
      });

      var jsonResponse = parseCleanJson(res.body.toString());
      if (jsonResponse['success']) {
        await AppData.saveAccessToken(jsonResponse['data']['token']);
        await AppData.saveName(name);
        return true;
      } else {
        ErrorHandler().showError(ErrorEnum.error, jsonResponse);
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}

Map<String, dynamic> parseCleanJson(String response) {
// Find first JSON object start
  final int jsonStart = response.indexOf('{');

  if (jsonStart == -1) {
    throw Exception('Invalid response: No JSON found');
  }

  final String cleanJson = response.substring(jsonStart);

  return jsonDecode(cleanJson);
}
