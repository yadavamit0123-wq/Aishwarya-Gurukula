import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:webinar/app/services/authentication_service/authentication_service.dart';
import 'package:webinar/app/services/authentication_service/firebase_phone_auth_service.dart';
import 'package:webinar/app/widgets/authentication_widget/register_widget/register_widget.dart';
import 'package:webinar/common/common.dart';
import 'package:webinar/common/data/app_data.dart';
import 'package:webinar/common/enums/error_enum.dart';
import 'package:webinar/common/utils/firebase_phone_config.dart';

import '../../../common/data/api_public_data.dart';
import '../../../common/enums/page_name_enum.dart';
import '../../../common/utils/app_text.dart';
import '../../../config/assets.dart';
import '../../../config/colors.dart';
import '../../../config/styles.dart';
import '../../../common/components.dart';
import '../../../locator.dart';
import '../../providers/page_provider.dart';
import '../main_page/main_page.dart';

class VerifyCodePage extends StatefulWidget {
  static const String pageName = '/verify-code';
  const VerifyCodePage({super.key});

  @override
  State<VerifyCodePage> createState() => _VerifyCodePageState();
}

class _VerifyCodePageState extends State<VerifyCodePage> {
  late Map<String, dynamic> data;

  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  final FirebasePhoneAuthService _firebasePhoneAuth = FirebasePhoneAuthService();

  bool isEmptyInputs = true;
  bool isSendingData = false;
  bool isCodeAgain = false;
  bool isFirebaseSending = false;
  String? firebaseStatusMessage;
  bool _useBackendSms = false;

  bool get isEmailFlow => data.containsKey('email') && data['email'] != null;

  bool get useFirebasePhone {
    if (isEmailFlow || _useBackendSms) return false;
    final method = data['verification_method']?.toString();
    if (method == 'firebase') return true;
    if (method == 'sms') return false;
    return FirebasePhoneConfig.useFirebasePhoneAuth;
  }

  int get otpLength {
    if (isEmailFlow) return 5;
    if (_useBackendSms || data['verification_method']?.toString() == 'sms') {
      return 5;
    }
    return FirebasePhoneConfig.mobileOtpLength;
  }

  static bool _isFirebaseAppCheckError(String message) {
    final m = message.toLowerCase();
    return m.contains('app identifier') ||
        m.contains('play integrity') ||
        m.contains('recaptcha') ||
        m.contains('missing a valid app') ||
        m.contains('app-not-authorized');
  }

  String get usernameForVerification {
    if (data['username'] != null) {
      return data['username'].toString().replaceAll('+', '').replaceAll(' ', '');
    }
    final cc = data['countryCode']?.toString().replaceAll('+', '') ?? '';
    final phone = data['phone']?.toString() ?? '';
    return '$cc$phone';
  }

  String get phoneE164 {
    final cc = data['countryCode']?.toString() ?? '';
    final phone = data['phone']?.toString() ?? '';
    if (cc.startsWith('+')) return '$cc$phone';
    return '+$cc$phone';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      data = Map<String, dynamic>.from(ModalRoute.of(context)!.settings.arguments as Map);
      _setupOtpFields();
      if (useFirebasePhone) {
        _startFirebaseOtp();
      }
    });
  }

  void _setupOtpFields() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();

    for (var i = 0; i < otpLength; i++) {
      final controller = TextEditingController();
      controller.addListener(_validateInputs);
      _controllers.add(controller);
      _focusNodes.add(FocusNode());
    }
    setState(() {});
  }

  void _validateInputs() {
    final complete = getCode().length == otpLength;
    if (complete != !isEmptyInputs) {
      setState(() => isEmptyInputs = !complete);
    }
  }

  String getCode() {
    return _controllers.map((c) => c.text.trim()).join();
  }

  void onPastedCode(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    FocusScope.of(navigatorKey.currentContext!).unfocus();
    _validateInputs();
  }

  Future<void> _fallbackToBackendSms(String firebaseError) async {
    setState(() {
      _useBackendSms = true;
      data['verification_method'] = 'sms';
      isFirebaseSending = true;
      firebaseStatusMessage = 'Sending OTP to your phone…';
    });
    _setupOtpFields();

    final resend = await AuthenticationService.resendPhoneVerification(data);
    if (!mounted) return;

    setState(() {
      isFirebaseSending = false;
      if (resend.sent) {
        firebaseStatusMessage = 'Enter the ${otpLength}-digit code sent by SMS.';
      } else if (resend.smsLikelyDisabled) {
        firebaseStatusMessage =
            'Firebase OTP failed. Server SMS is off — fix Firebase SHA or ask admin to enable SMS OTP.';
      } else {
        firebaseStatusMessage =
            'Could not send OTP. Please tap Resend or try again in a moment.';
      }
    });

    if (resend.sent) {
      showSnackBar(
        ErrorEnum.success,
        'Verification code sent to your phone by SMS.',
      );
    } else if (resend.smsLikelyDisabled) {
      showSnackBar(
        ErrorEnum.error,
        'OTP was not sent: admin has Firebase-only mode (SMS disabled). '
            'Add upload + Play SHA in Firebase, or disable “replaces SMS OTP” in admin.',
      );
    } else {
      showSnackBar(ErrorEnum.error, firebaseError);
    }
  }

  Future<void> _startFirebaseOtp() async {
    setState(() {
      isFirebaseSending = true;
      firebaseStatusMessage = 'Sending verification code…';
    });

    await _firebasePhoneAuth.sendOtp(
      phoneE164: phoneE164,
      onCodeSent: () {
        if (!mounted) return;
        setState(() {
          isFirebaseSending = false;
          firebaseStatusMessage = 'Enter the 6-digit code sent to your phone.';
        });
      },
      onFailed: (message) async {
        if (!mounted) return;
        if (_isFirebaseAppCheckError(message)) {
          await _fallbackToBackendSms(message);
          return;
        }
        setState(() {
          isFirebaseSending = false;
          firebaseStatusMessage = message;
        });
        showSnackBar(ErrorEnum.error, message);
      },
      onAutoVerified: (idToken) async {
        await _submitWithFirebaseToken(idToken);
      },
    );
  }

  Future<void> _submitWithFirebaseToken(String idToken) async {
    setState(() => isSendingData = true);
    final res = await AuthenticationService.verifyPhoneAccount(
      usernameForVerification,
      idToken: idToken,
    );
    await _afterVerifySuccess(res);
    if (mounted) setState(() => isSendingData = false);
  }

  Future<void> _submitCode() async {
    final code = getCode();
    if (code.length != otpLength) return;

    setState(() => isSendingData = true);

    bool res = false;
    if (isEmailFlow) {
      res = await AuthenticationService.verifyCode(data['user_id'], code);
    } else if (useFirebasePhone) {
      final firebaseResult = await _firebasePhoneAuth.verifySmsCode(code);
      if (firebaseResult.idToken != null) {
        res = await AuthenticationService.verifyPhoneAccount(
          usernameForVerification,
          idToken: firebaseResult.idToken,
        );
        await _firebasePhoneAuth.signOutFirebaseSession();
      } else {
        showSnackBar(ErrorEnum.error, firebaseResult.error);
      }
    } else {
      res = await AuthenticationService.verifyPhoneAccount(
        usernameForVerification,
        code: code,
      );
    }

    await _afterVerifySuccess(res);
    if (mounted) setState(() => isSendingData = false);
  }

  Future<void> _afterVerifySuccess(bool res) async {
    if (!res) return;

    if (Platform.isAndroid) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }

    if (data['from_login'] == true) {
      locator<PageProvider>().setPage(PageNames.home);
      nextRoute(MainPage.pageName, isClearBackRoutes: true);
      return;
    }

    AppData.canShowFinalizeSheet = true;
    locator<PageProvider>().setPage(PageNames.home);
    nextRoute(MainPage.pageName, isClearBackRoutes: true, arguments: data['user_id']);
  }

  void _clearOtpFields() {
    for (final c in _controllers) {
      c.clear();
    }
    setState(() => isEmptyInputs = true);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controllers.isEmpty) {
      return directionality(child: Scaffold(body: loading()));
    }

    return directionality(
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                AppAssets.introBgPng,
                width: getSize().width,
                height: getSize().height,
                fit: BoxFit.cover,
                colorBlendMode: BlendMode.clear,
                color: isLightMode() ? null : greyFA,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: padding(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    space(getSize().height * .11),
                    Row(
                      children: [
                        Text(appText.accountVerification, style: style24Bold()),
                        space(0, width: 4),
                        SvgPicture.asset(AppAssets.emoji2Svg),
                      ],
                    ),
                    Text(
                      useFirebasePhone
                          ? 'Enter the verification code from Firebase SMS.'
                          : appText.accountVerificationDesc,
                      style: style14Regular().copyWith(color: greyA5),
                    ),
                    if (firebaseStatusMessage != null) ...[
                      space(8),
                      Text(
                        firebaseStatusMessage!,
                        style: style12Regular().copyWith(color: greyA5),
                      ),
                    ],
                    if (isFirebaseSending) ...[
                      space(12),
                      Center(child: loading()),
                    ],
                    const Spacer(),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_controllers.length, (index) {
                          return Padding(
                            padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
                            child: RegisterWidget.codeInput(
                              _controllers[index],
                              _focusNodes[index],
                              index < _controllers.length - 1 ? _focusNodes[index + 1] : null,
                              index > 0 ? _focusNodes[index - 1] : null,
                              onPastedCode,
                            ),
                          );
                        }),
                      ),
                    ),
                    const Spacer(),
                    Center(
                      child: button(
                        onTap: () async {
                          if (!isEmptyInputs && !isSendingData) {
                            await _submitCode();
                          }
                        },
                        width: getSize().width,
                        height: 52,
                        text: appText.verifyMyAccount,
                        bgColor: isEmptyInputs ? greyCF : green77(),
                        textColor: Colors.white,
                        borderColor: Colors.transparent,
                        isLoading: isSendingData,
                      ),
                    ),
                    space(16),
                    Center(
                      child: Text(
                        appText.haventReceiveTheCode,
                        style: style14Regular().copyWith(color: greyB2),
                      ),
                    ),
                    Center(
                      child: isCodeAgain
                          ? loading()
                          : GestureDetector(
                              onTap: () async {
                                setState(() => isCodeAgain = true);

                                if (isEmailFlow) {
                                  if (PublicData.apiConfigData['register_method'] == 'email') {
                                    await AuthenticationService.registerWithEmail(
                                      PublicData.apiConfigData?['register_method'],
                                      data['email'],
                                      data['password'],
                                      data['retypePassword'],
                                      'user',
                                      [],
                                    );
                                  }
                                } else if (useFirebasePhone && !_useBackendSms) {
                                  await _startFirebaseOtp();
                                } else {
                                  final resend =
                                      await AuthenticationService.resendPhoneVerification(data);
                                  if (resend.sent) {
                                    showSnackBar(
                                      ErrorEnum.success,
                                      'Verification code sent to your phone by SMS.',
                                    );
                                  } else if (resend.smsLikelyDisabled) {
                                    showSnackBar(
                                      ErrorEnum.error,
                                      'SMS OTP is disabled on server (Firebase-only mode).',
                                    );
                                  }
                                }

                                _clearOtpFields();
                                setState(() => isCodeAgain = false);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Text(appText.resendCode, style: style16Regular()),
                            ),
                    ),
                    const Spacer(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
