import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/auth/presentation/web_login_page.dart';
import 'package:x300/shared/presentation/app_snack_bar.dart';

class LoginPage extends ConsumerStatefulWidget
{
    const LoginPage({
        required this.authState,
        super.key,
    });

    final AuthState authState;

    @override
    ConsumerState<LoginPage> createState()
    {
        return _LoginPageState();
    }
}

class _LoginPageState extends ConsumerState<LoginPage>
{
    final TextEditingController _usernameController =
        TextEditingController();
    final TextEditingController _passwordController =
        TextEditingController();
    final TextEditingController _captchaController =
        TextEditingController();
    final FocusNode _passwordFocus = FocusNode();
    final FocusNode _captchaFocus = FocusNode();
    bool _passwordVisible = false;

    @override
    void dispose()
    {
        _usernameController.dispose();
        _passwordController.dispose();
        _captchaController.dispose();
        _passwordFocus.dispose();
        _captchaFocus.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        final bool needsCaptcha =
            widget.authState.status == AuthStatus.captchaRequired;
        final bool supportsWebLogin =
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
        return Scaffold(
            body: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: AutofillGroup(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: <Widget>[
                                                _buildHeader(context),
                                                const SizedBox(height: 28),
                                                TextField(
                                                    controller:
                                                        _usernameController,
                                                    autofocus: true,
                                                    autofillHints: const <String>[
                                                        AutofillHints.username,
                                                    ],
                                                    textInputAction:
                                                        TextInputAction.next,
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                '用户名 / Email / UID',
                                                            prefixIcon: Icon(
                                                                Remix.user_line,
                                                            ),
                                                            border:
                                                                OutlineInputBorder(),
                                                        ),
                                                    onSubmitted: (_) =>
                                                        _passwordFocus
                                                            .requestFocus(),
                                                ),
                                                const SizedBox(height: 12),
                                                TextField(
                                                    controller:
                                                        _passwordController,
                                                    focusNode: _passwordFocus,
                                                    autofillHints: const <String>[
                                                        AutofillHints.password,
                                                    ],
                                                    obscureText:
                                                        !_passwordVisible,
                                                    textInputAction: needsCaptcha
                                                        ? TextInputAction.next
                                                        : TextInputAction.done,
                                                    decoration: InputDecoration(
                                                        labelText: '密码',
                                                        prefixIcon: const Icon(
                                                            Remix.lock_password_line,
                                                        ),
                                                        suffixIcon: IconButton(
                                                            onPressed: ()
                                                            {
                                                                setState(()
                                                                {
                                                                    _passwordVisible =
                                                                        !_passwordVisible;
                                                                });
                                                            },
                                                            icon: Icon(
                                                                _passwordVisible
                                                                    ? Remix.eye_off_line
                                                                    : Remix.eye_line,
                                                            ),
                                                        ),
                                                        border:
                                                            const OutlineInputBorder(),
                                                    ),
                                                    onSubmitted: (_)
                                                    {
                                                        if (needsCaptcha)
                                                        {
                                                            _captchaFocus
                                                                .requestFocus();
                                                        }
                                                        else
                                                        {
                                                            _submit();
                                                        }
                                                    },
                                                ),
                                                if (needsCaptcha) ...<Widget>[
                                                    const SizedBox(height: 12),
                                                    _buildCaptcha(context),
                                                ],
                                                if (widget.authState.message
                                                    .isNotEmpty) ...<Widget>[
                                                    const SizedBox(height: 12),
                                                    Text(
                                                        widget.authState.message,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                            color: Theme.of(
                                                                context,
                                                            ).colorScheme.error,
                                                            fontSize: 12,
                                                        ),
                                                    ),
                                                ],
                                                const SizedBox(height: 20),
                                                SizedBox(
                                                    height: 44,
                                                    child: ElevatedButton(
                                                        onPressed: _submit,
                                                        child: const Text('登录'),
                                                    ),
                                                ),
                                                if (supportsWebLogin) ...<Widget>[
                                                    const SizedBox(height: 8),
                                                    TextButton.icon(
                                                        onPressed: _openWebLogin,
                                                        icon: const Icon(
                                                            Remix.global_line,
                                                        ),
                                                        label: const Text(
                                                            '网页登录',
                                                        ),
                                                    ),
                                                ],
                                                const SizedBox(height: 12),
                                                const Text(
                                                    '凭据保存在系统安全存储中，登录会话仅用于访问你有权限查看的论坛内容。',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 11,
                                                        height: 1.4,
                                                    ),
                                                ),
                                            ],
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        );
    }

    Widget _buildHeader(BuildContext context)
    {
        return Column(
            children: <Widget>[
                CircleAvatar(
                    radius: 34,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    child: Icon(
                        Remix.book_open_line,
                        size: 34,
                        color: Theme.of(context).colorScheme.primary,
                    ),
                ),
                const SizedBox(height: 14),
                Text(
                    '300X',
                    style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                    '登录百合会论坛',
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                    ),
                ),
            ],
        );
    }

    Widget _buildCaptcha(BuildContext context)
    {
        final CaptchaChallenge captcha = widget.authState.captcha!;
        return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
                Expanded(
                    child: TextField(
                        controller: _captchaController,
                        focusNode: _captchaFocus,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                            labelText: '验证码',
                            prefixIcon: Icon(Remix.shield_keyhole_line),
                            border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _submit(),
                    ),
                ),
                const SizedBox(width: 8),
                InkWell(
                    onTap: () => ref
                        .read(authControllerProvider.notifier)
                        .refreshCaptcha(),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                        width: 118,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(4),
                        ),
                        child: Image.memory(
                            captcha.imageBytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                        ),
                    ),
                ),
            ],
        );
    }

    void _submit()
    {
        final String username = _usernameController.text.trim();
        final String password = _passwordController.text;
        if (username.isEmpty || password.isEmpty)
        {
            ScaffoldMessenger.of(context).showSnackBar(
                const AppSnackBar(content: Text('请输入账号和密码')),
            );
            return;
        }
        ref.read(authControllerProvider.notifier).login(
              username: username,
              password: password,
              captcha: _captchaController.text,
          );
    }

    Future<void> _openWebLogin() async
    {
        await Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) => const WebLoginPage(),
            ),
        );
    }
}
