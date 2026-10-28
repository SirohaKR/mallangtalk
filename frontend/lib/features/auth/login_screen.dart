import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/mallangtalk_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../settings/user_profile.dart';
import 'auth_state.dart';

/// [초보자 노트] 말랑톡 서버에서 열면 처음에 보이는 로그인 화면입니다.
/// 아이디·비밀번호로 로그인하고, 아래 '회원가입'을 누르면 같은 화면이 가입 칸으로 바뀌어요.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  final _nickname = TextEditingController();
  var _signup = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    String? problem;
    if (username.isEmpty) problem = '아이디를 적어 주세요';
    if (problem == null && password.isEmpty) problem = '비밀번호를 적어 주세요';
    if (problem == null && _signup && password != _passwordAgain.text) problem = '비밀번호 확인이 달라요';
    if (problem != null) return setState(() => _error = problem);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      if (_signup) {
        await auth.signup(username, password, _nickname.text);
        // 가입할 때 정한 닉네임을 캐릭터가 부를 기본 별명으로 (이미 정해 둔 게 없을 때만)
        final profile = ref.read(userProfileProvider);
        final nickname = ref.read(authProvider).user?.nickname ?? '';
        if (!profile.hasNickname && nickname.isNotEmpty) {
          await ref.read(userProfileProvider.notifier).save(nickname: nickname, intro: profile.intro);
        }
      } else {
        await auth.login(username, password);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chatRoomBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.chat_bubble_rounded, size: 48, color: AppColors.primaryPink),
                  const SizedBox(height: 8),
                  Text('말랑톡', textAlign: TextAlign.center, style: AppTextStyles.appBarTitle.copyWith(fontSize: 26)),
                  const SizedBox(height: 4),
                  Text(_signup ? '새 계정을 만들어요' : '로그인하고 캐릭터와 이야기해요',
                      textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _username,
                    autofillHints: [_signup ? AutofillHints.newUsername : AutofillHints.username],
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '아이디',
                      helperText: _signup ? '영문·숫자·밑줄(_) 3~20자' : null,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  if (_signup) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _nickname,
                      maxLength: 12,
                      decoration: const InputDecoration(labelText: '닉네임 (선택)', helperText: '다른 유저에게 제작자 이름으로 보여요'),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      helperText: _signup ? '8자 이상' : null,
                    ),
                    textInputAction: _signup ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: _signup ? null : (_) => _submit(),
                  ),
                  if (_signup) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _passwordAgain,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '비밀번호 확인'),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, textAlign: TextAlign.center,
                        style: AppTextStyles.systemNotice.copyWith(color: AppColors.primaryPink)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_signup ? '회원가입' : '로그인'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _signup = !_signup;
                              _error = null;
                            }),
                    child: Text(_signup ? '이미 계정이 있어요 · 로그인' : '계정이 없나요? 회원가입'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
