import 'dart:typed_data';

enum AuthStatus
{
    unauthenticated,
    captchaRequired,
    authenticated,
}

class AuthState
{
    const AuthState({
        required this.status,
        this.username = '',
        this.message = '',
        this.captcha,
        this.avatarUri,
        this.webFallbackAvailable = false,
    });

    const AuthState.unauthenticated({
        String message = '',
        bool webFallbackAvailable = false,
    })
        : this(
              status: AuthStatus.unauthenticated,
              message: message,
              webFallbackAvailable: webFallbackAvailable,
          );

    const AuthState.authenticated(
        String username, {
        Uri? avatarUri,
    })
        : this(
              status: AuthStatus.authenticated,
              username: username,
              avatarUri: avatarUri,
          );

    const AuthState.captchaRequired({
        required CaptchaChallenge captcha,
        String message = '请输入验证码后重试',
    }) : this(
              status: AuthStatus.captchaRequired,
              message: message,
              captcha: captcha,
          );

    final AuthStatus status;
    final String username;
    final String message;
    final CaptchaChallenge? captcha;
    final Uri? avatarUri;
    final bool webFallbackAvailable;
}

class CaptchaChallenge
{
    const CaptchaChallenge({
        required this.imageBytes,
    });

    final Uint8List imageBytes;
}

class LoginForm
{
    const LoginForm({
        required this.action,
        required this.fields,
        required this.usernameField,
        required this.passwordField,
        this.captchaField,
        this.captchaImage,
    });

    final Uri action;
    final Map<String, String> fields;
    final String usernameField;
    final String passwordField;
    final String? captchaField;
    final Uri? captchaImage;

    bool get requiresCaptcha =>
        captchaField != null && captchaImage != null;
}

class ParsedAuthPage
{
    const ParsedAuthPage({
        required this.loggedIn,
        required this.message,
        this.form,
    });

    final bool loggedIn;
    final String message;
    final LoginForm? form;
}
