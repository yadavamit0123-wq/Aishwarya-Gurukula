import 'package:firebase_auth/firebase_auth.dart';

class FirebasePhoneAuthService {
  String? _verificationId;
  int? _resendToken;

  String? get verificationId => _verificationId;

  Future<void> sendOtp({
    required String phoneE164,
    required void Function() onCodeSent,
    required void Function(String message) onFailed,
    void Function(String idToken)? onAutoVerified,
  }) async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneE164,
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
          final token = await userCred.user?.getIdToken();
          if (token != null && onAutoVerified != null) {
            onAutoVerified(token);
          }
        } catch (_) {}
      },
      verificationFailed: (FirebaseAuthException e) {
        onFailed(e.message ?? 'Phone verification failed');
      },
      codeSent: (String verificationId, int? forceResendingToken) {
        _verificationId = verificationId;
        _resendToken = forceResendingToken;
        onCodeSent();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<({String? idToken, String? error})> verifySmsCode(String smsCode) async {
    final vid = _verificationId;
    if (vid == null || vid.isEmpty) {
      return (idToken: null, error: 'Verification session expired. Resend code.');
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: smsCode,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final token = await userCred.user?.getIdToken();
      if (token == null || token.isEmpty) {
        return (idToken: null, error: 'Could not get Firebase token');
      }
      return (idToken: token, error: null);
    } on FirebaseAuthException catch (e) {
      return (idToken: null, error: e.message ?? 'Invalid OTP');
    } catch (_) {
      return (idToken: null, error: 'Invalid OTP');
    }
  }

  Future<void> signOutFirebaseSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}
