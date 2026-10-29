import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../settings/byok_settings.dart';

/// 대화방에서 자유대화 AI(회사·모델)를 바로 고르는 시트
Future<void> showChatAiSheet(BuildContext context, {required Color accent, String? roomId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceWhite,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _ChatAiSheet(accent: accent, roomId: roomId),
  );
}

/// [초보자 노트] 설정까지 가지 않고 대화방에서 AI를 바꾸는 곳.
/// 키가 있는 회사는 모델만 고르면 되고, 키가 없는 회사를 누르면 그 자리에서 키를 붙여 넣어 연결해요.
/// 대화방에서 열면 '이 대화만 / 모든 대화 기본으로' 중 어디에 쓸지 고를 수 있어요.
/// 모든 대화 기본은 설정 > AI 연결과 같은 값이에요.
class _ChatAiSheet extends ConsumerStatefulWidget {
  const _ChatAiSheet({required this.accent, this.roomId});

  final Color accent;

  /// 대화방에서 열었으면 그 방 (없으면 모든 대화 기본만 바꿈)
  final String? roomId;

  @override
  ConsumerState<_ChatAiSheet> createState() => _ChatAiSheetState();
}

class _ChatAiSheetState extends ConsumerState<_ChatAiSheet> {
  String? get _room => widget.roomId;
  ByokSettings _active() => _room == null ? ref.read(byokSettingsProvider) : ref.read(roomByokProvider(_room!));
  late AiProvider _provider = _active().provider;

  /// true면 이 대화방에만 (이미 '이 대화만'으로 골라 둔 방이면 처음부터 true)
  late bool _onlyHere = _room != null && ref.read(roomAiChoiceProvider(_room!)) != null;
  final _key = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _use({String? apiKey, String? model}) async {
    final notifier = ref.read(byokSettingsProvider.notifier);
    final current = notifier.peek(_provider);
    final active = _active();
    final pickedModel = model ?? (active.provider == _provider ? active.model : current.model);
    setState(() => _saving = true);
    if (_onlyHere && _room != null) {
      if (apiKey != null && apiKey.trim().isNotEmpty) await notifier.saveKey(_provider, apiKey);
      await ref.read(roomAiChoiceProvider(_room!).notifier).set(_provider, pickedModel);
    } else {
      await notifier.save(provider: _provider, apiKey: apiKey ?? '', model: pickedModel);
      if (_room != null) await ref.read(roomAiChoiceProvider(_room!).notifier).clear();
    }
    if (mounted) setState(() => _saving = false);
  }

  /// 적용할 곳을 바꾸면 지금 이 방에서 쓰는 AI를 그쪽에 그대로 옮김
  Future<void> _setScope(bool onlyHere) async {
    if (onlyHere == _onlyHere) return;
    final active = _active();
    setState(() {
      _onlyHere = onlyHere;
      _provider = active.provider;
    });
    if (active.canUseAi) await _use(model: active.model);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(byokSettingsProvider);
    final active = _room == null ? ref.watch(byokSettingsProvider) : ref.watch(roomByokProvider(_room!));
    final notifier = ref.read(byokSettingsProvider.notifier);
    final picked = _provider == active.provider ? active : notifier.peek(_provider);
    final accent = widget.accent;

    Widget card({
      required String title,
      required String note,
      required bool on,
      required VoidCallback onTap,
      Key? key,
    }) =>
        InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: _saving ? null : onTap,
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: on ? Color.lerp(AppColors.surfaceWhite, accent, 0.08) : AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? accent : AppColors.borderLight, width: on ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.choiceButton.copyWith(color: AppColors.textPrimary)),
                Text(note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('자유대화 AI', style: AppTextStyles.appBarTitle),
            const SizedBox(height: 4),
            Text(
                _room == null
                    ? 'AI가 캐릭터가 되어 자유롭게 답해요. 고른 AI는 모든 대화에 쓰여요.'
                    : _onlyHere
                        ? 'AI가 캐릭터가 되어 자유롭게 답해요. 고른 AI는 이 대화방에만 쓰여요.'
                        : 'AI가 캐릭터가 되어 자유롭게 답해요. 고른 AI는 따로 정하지 않은 모든 대화에 쓰여요.',
                style: AppTextStyles.systemNotice),
            if (_room != null) ...[
              const SizedBox(height: 12),
              const Text('적용할 곳', style: AppTextStyles.speakerName),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                key: const ValueKey('ai_scope'),
                segments: const [
                  ButtonSegment(value: true, label: Text('이 대화만')),
                  ButtonSegment(value: false, label: Text('모든 대화 기본으로')),
                ],
                selected: {_onlyHere},
                showSelectedIcon: false,
                onSelectionChanged: _saving ? null : (v) => _setScope(v.first),
              ),
            ],
            const SizedBox(height: 14),
            const Text('AI 회사', style: AppTextStyles.speakerName),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final p in AiProvider.values) ...[
                  if (p != AiProvider.values.first) const SizedBox(width: 8),
                  Expanded(
                    child: card(
                      key: ValueKey('ai_provider_${p.name}'),
                      title: aiShortName(p),
                      note: notifier.peek(p).canUseAi ? '연결됨' : '키 없음',
                      on: p == _provider,
                      onTap: () {
                        setState(() => _provider = p);
                        // 이미 쓸 수 있는 회사면 바로 바꿈
                        if (notifier.peek(p).canUseAi) _use();
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (picked.canUseAi) ...[
              const Text('모델', style: AppTextStyles.speakerName),
              const SizedBox(height: 6),
              for (final m in _provider.models)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: card(
                    key: ValueKey('ai_model_${m.id}'),
                    title: m.label,
                    note: m.note,
                    on: _provider == active.provider && active.model == m.id,
                    onTap: () => _use(model: m.id),
                  ),
                ),
              if (picked.modelOption == null)
                Text('지금 쓰는 모델: ${picked.model} (설정에서 직접 입력한 모델)', style: AppTextStyles.messageTime),
            ] else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Color.lerp(AppColors.surfaceWhite, accent, 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${aiShortName(_provider)} 키를 넣으면 바로 쓸 수 있어요', style: AppTextStyles.choiceButton),
                    const SizedBox(height: 10),
                    const Text('1. 아래 링크에서 키를 만들고 복사해요', style: AppTextStyles.systemNotice),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: accent),
                        onPressed: () => launchUrl(Uri.parse(aiKeyPage(_provider)), webOnlyWindowName: '_blank'),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('키 받으러 가기'),
                      ),
                    ),
                    const Text('2. 여기에 붙여 넣고 연결해요. 키는 이 기기에만 저장돼요', style: AppTextStyles.systemNotice),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('chat_ai_key'),
                      controller: _key,
                      obscureText: true,
                      decoration: InputDecoration(hintText: _provider.keyHint),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(46)),
                      onPressed: _saving || _key.text.trim().isEmpty
                          ? null
                          : () async {
                              await _use(apiKey: _key.text, model: picked.model);
                              _key.clear();
                            },
                      child: const Text('연결하고 쓰기'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
