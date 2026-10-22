import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/claude_chat_client.dart';
import '../../core/network/claude_studio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/file_io.dart';
import '../add/add_character_screen.dart';
import '../library/character_library.dart';
import '../settings/byok_settings.dart';
import 'character_import.dart';
import 'script_workbook.dart';
import 'template_scenario.dart';

enum _StudioMode { excel, ai }

/// [초보자 노트] 캐릭터 만들기 화면입니다.
/// - 엑셀 대본: 템플릿을 받아 모든 대사를 직접 쓰고 올리기
/// - AI로 만들기: 캐릭터 설정만 적으면 호감도 단계별 이벤트·일상 대화·엔딩과 대사를 Claude가 생성
///   (만든 대본은 엑셀로 내보내서 고친 뒤 다시 올릴 수 있음)
class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen>
    with AutomaticKeepAliveClientMixin {
  _StudioMode _mode = _StudioMode.excel;

  // 엑셀 대본
  ScriptWorkbookResult? _excelResult;
  List<String> _excelErrors = const [];

  // AI 생성 설정
  final _name = TextEditingController();
  final _status = TextEditingController();
  final _personality = TextEditingController();
  final _relationship = TextEditingController();
  double _typing = 1.0;
  final List<_StageDraft> _stages = [
    _StageDraft('어색한 사이', 0),
    _StageDraft('친구', 20),
    _StageDraft('썸', 45),
  ];
  int _eventsPerStage = 2;
  int _dailiesPerStage = 3;

  bool _generating = false;
  String _progressText = '';
  double _progress = 0;
  ScenarioBundle? _aiResult;
  String? _aiError;

  @override
  bool get wantKeepAlive => true; // 탭을 옮겨도 쓰던 내용 유지

  @override
  void dispose() {
    for (final c in [_name, _status, _personality, _relationship]) {
      c.dispose();
    }
    for (final s in _stages) {
      s.dispose();
    }
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ───────────── 엑셀 ─────────────

  Future<void> _downloadTemplate() async {
    await FileIO.save(
      fileName: '말랑톡_대본_템플릿.xlsx',
      bytes: ScriptWorkbook.encode(templateScenario()),
      mimeType: FileIO.xlsxMime,
    );
  }

  Future<void> _uploadExcel() async {
    final file = await FileIO.pick(extensions: ['xlsx']);
    if (file == null) return;
    setState(() {
      try {
        final result = ScriptWorkbook.decode(file.bytes);
        _excelResult = ScriptWorkbookResult(result.bundle, [
          ...result.warnings,
          if (!bestPathClears(result.bundle))
            '좋은 선택만 골라도 모든 이벤트를 열 수 없어요. 선택지 호감도나 단계 점수를 확인해 주세요.',
        ]);
        _excelErrors = const [];
      } on ScriptWorkbookException catch (e) {
        _excelResult = null;
        _excelErrors = e.errors;
      }
    });
  }

  // ───────────── AI ─────────────

  List<AffectionStage>? _buildStages() {
    final drafts = [..._stages]..sort((a, b) => a.start.compareTo(b.start));
    if (drafts.isEmpty || drafts.first.start != 0) return null;
    return [
      for (var i = 0; i < drafts.length; i++)
        AffectionStage(
          minScore: drafts[i].start,
          maxScore: i + 1 < drafts.length ? drafts[i + 1].start - 1 : 100,
          stageLabel: drafts[i].name.text.trim(),
        ),
    ];
  }

  StudioBrief _brief() {
    final stages = _buildStages();
    return StudioBrief(
      name: _name.text,
      statusMessage: _status.text,
      personality: _personality.text,
      relationship: _relationship.text,
      typingSpeedMultiplier: _typing,
      stages: stages ?? const [],
      eventsPerStage: _eventsPerStage,
      dailiesPerStage: _dailiesPerStage,
    );
  }

  Future<void> _generate() async {
    final byok = ref.read(byokSettingsProvider);
    final stages = _buildStages();
    if (_name.text.trim().isEmpty) return _toast('캐릭터 이름을 적어 주세요');
    if (_personality.text.trim().length < 10) {
      return _toast('성격·말투·취미를 조금 더 자세히 적어 주세요');
    }
    if (stages == null || stages.any((s) => s.stageLabel.isEmpty)) {
      return _toast('호감도 단계 이름을 모두 적고, 첫 단계는 0점부터 시작해 주세요');
    }
    if (stages.map((s) => s.minScore).toSet().length != stages.length) {
      return _toast('호감도 단계 시작 점수가 겹쳐요');
    }
    if (!byok.hasKey) return _toast('설정에서 Claude API 키를 먼저 넣어 주세요');

    setState(() {
      _generating = true;
      _aiError = null;
      _aiResult = null;
      _progress = 0;
      _progressText = '시작하는 중';
    });
    try {
      final bundle = await ref.read(claudeStudioClientProvider).generate(
            apiKey: byok.apiKey!,
            model: byok.model,
            brief: _brief(),
            onProgress: (message, done, total) {
              if (!mounted) return;
              setState(() {
                _progressText = message;
                _progress = total == 0 ? 0 : done / total;
              });
            },
          );
      if (mounted) setState(() => _aiResult = bundle);
    } on ClaudeChatException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } catch (e) {
      if (mounted) setState(() => _aiError = '만드는 중 문제가 생겼어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    icon: Icons.table_chart_outlined,
                    label: '엑셀 대본으로',
                    note: '모든 대사를 직접',
                    selected: _mode == _StudioMode.excel,
                    onTap: () => setState(() => _mode = _StudioMode.excel),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.auto_awesome_outlined,
                    label: 'AI로 만들기',
                    note: '설정만 적으면 자동',
                    selected: _mode == _StudioMode.ai,
                    onTap: () => setState(() => _mode = _StudioMode.ai),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_mode == _StudioMode.excel) ..._excelSection() else ..._aiSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _excelSection() => [
        const Text('엑셀 대본으로 만들기', style: AppTextStyles.appBarTitle),
        const SizedBox(height: 6),
        const Text(
          '템플릿에 캐릭터 설정, 호감도 단계(이름·점수), 이벤트·일상 대화, 모든 대사와 선택지를 적어서 올려요. '
          '템플릿 첫 시트에 쓰는 법이 있고, 예시 캐릭터가 채워져 있어요.',
          style: AppTextStyles.systemNotice,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('템플릿 받기'),
                onPressed: _downloadTemplate,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('대본 올리기'),
                onPressed: _uploadExcel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '이미 있는 캐릭터의 대본이 궁금하면 내 캐릭터 → 프로필 → 엑셀로 내보내기',
          style: AppTextStyles.messageTime,
        ),
        if (_excelErrors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ProblemList(title: '고쳐야 할 곳이 있어요', items: _excelErrors, isError: true),
        ],
        if (_excelResult != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ResultCard(
            bundle: _excelResult!.bundle,
            warnings: _excelResult!.warnings,
            onAdd: () async {
              await addCharacterAndAnnounce(
                  context, ref, _excelResult!.bundle, CharacterSource.created);
              if (mounted) setState(() => _excelResult = null);
            },
          ),
        ],
      ];

  List<Widget> _aiSection() {
    final byok = ref.watch(byokSettingsProvider);
    final model = ClaudeModelOption.all.where((m) => m.id == byok.model).firstOrNull;
    final brief = _brief();
    return [
      const Text('캐릭터 설정', style: AppTextStyles.appBarTitle),
      const SizedBox(height: AppSpacing.sm),
      _Field(controller: _name, label: '이름', hint: '예: 윤도하'),
      _Field(controller: _status, label: '상태메시지', hint: '예: 두부 집사 / 토요일 홍대'),
      _Field(
        controller: _personality,
        label: '성격·말투·취미·세계관',
        hint: '나이, 직업, 말투 습관(ㅋㅋ를 자주 씀 등), 취미, 관심사, 숨기고 있는 마음까지 자세할수록 좋아요',
        lines: 5,
      ),
      _Field(controller: _relationship, label: '나와의 관계', hint: '예: 알게 된 지 1년 된 남사친'),
      const SizedBox(height: AppSpacing.sm),
      const Text('타자 스타일', style: AppTextStyles.speakerName),
      const SizedBox(height: 6),
      TypingStylePicker(value: _typing, onChanged: (v) => setState(() => _typing = v)),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          const Expanded(child: Text('호감도 단계', style: AppTextStyles.appBarTitle)),
          if (_stages.length < 6)
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('단계 추가'),
              onPressed: () => setState(() {
                final last = _stages.map((s) => s.start).fold(0, (a, b) => a > b ? a : b);
                _stages.add(_StageDraft('', (last + 20).clamp(1, 95)));
              }),
            ),
        ],
      ),
      const Text(
        '단계마다 이름과 시작 점수를 정해요. 그 단계에 맞는 이벤트와 일상 대화가 따로 만들어져요. 점수는 화면에 안 보여요.',
        style: AppTextStyles.systemNotice,
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final stage in _stages)
        _StageRow(
          draft: stage,
          canRemove: _stages.length > 1,
          onChanged: () => setState(() {}),
          onRemove: () => setState(() {
            _stages.remove(stage);
            stage.dispose();
          }),
        ),
      const SizedBox(height: AppSpacing.md),
      const Text('분량 (단계마다)', style: AppTextStyles.speakerName),
      _Counter(
        label: '호감도 이벤트',
        value: _eventsPerStage,
        min: 1,
        max: 4,
        onChanged: (v) => setState(() => _eventsPerStage = v),
      ),
      _Counter(
        label: '일상 대화',
        value: _dailiesPerStage,
        min: 0,
        max: 6,
        onChanged: (v) => setState(() => _dailiesPerStage = v),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '총 ${brief.totalTalks}개 대화(엔딩 포함)를 만들어요. '
        '${byok.hasKey ? '설정의 내 키로 ${model?.label ?? byok.model}를 써요. 몇 분 걸릴 수 있어요.' : ''}',
        style: AppTextStyles.systemNotice,
      ),
      if (!byok.hasKey)
        TextButton(
          onPressed: () => context.go('/settings'),
          child: const Text('설정에서 Claude API 키 넣기 →'),
        ),
      const SizedBox(height: AppSpacing.sm),
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
        label: Text(_generating ? '만드는 중...' : 'AI로 이벤트·대사 만들기'),
        onPressed: _generating ? null : _generate,
      ),
      if (_generating) ...[
        const SizedBox(height: AppSpacing.md),
        LinearProgressIndicator(
          value: _progress == 0 ? null : _progress,
          color: AppColors.aiActivePurple,
          backgroundColor: AppColors.borderLight,
        ),
        const SizedBox(height: 6),
        Text(_progressText, style: AppTextStyles.systemNotice),
      ],
      if (_aiError != null) ...[
        const SizedBox(height: AppSpacing.md),
        ProblemList(title: '만들지 못했어요', items: [_aiError!], isError: true),
      ],
      if (_aiResult != null) ...[
        const SizedBox(height: AppSpacing.md),
        _ResultCard(
          bundle: _aiResult!,
          warnings: const [],
          onExport: () => FileIO.save(
            fileName: '${FileIO.safeName(_aiResult!.character.name)}_대본.xlsx',
            bytes: ScriptWorkbook.encode(_aiResult!),
            mimeType: FileIO.xlsxMime,
          ),
          onAdd: () async {
            await addCharacterAndAnnounce(context, ref, _aiResult!, CharacterSource.created);
            if (mounted) setState(() => _aiResult = null);
          },
        ),
      ],
    ];
  }
}

class _StageDraft {
  _StageDraft(String name, this.start) : name = TextEditingController(text: name);

  final TextEditingController name;
  int start;

  void dispose() => name.dispose();
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _StageDraft draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: draft.name,
              decoration: const InputDecoration(hintText: '단계 이름 (예: 신경 쓰이는 친구)'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 78,
            child: TextFormField(
              key: ValueKey(draft),
              initialValue: '${draft.start}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(suffixText: '점~'),
              onChanged: (v) {
                draft.start = (int.tryParse(v) ?? 0).clamp(0, 99);
                onChanged();
              },
            ),
          ),
          IconButton(
            tooltip: '단계 빼기',
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

/// 타자 스타일 고르기 + 미리 듣기 같은 예상 시간 표시
class TypingStylePicker extends StatelessWidget {
  const TypingStylePicker({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // 채팅방과 같은 계산: 멈칫 0.5초 + (0.7초 + 글자당 0.15초)
    const sample = '오늘 뭐해? 나 방금 일어남';
    final seconds = (500 + 700 + sample.length * 150) * value / 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final style in TypingStyle.all)
              _Pill(
                label: style.label,
                selected: (style.multiplier - value).abs() < 0.01,
                onTap: () => onChanged(style.multiplier),
              ),
          ],
        ),
        Slider(
          value: value.clamp(0.5, 2.0),
          min: 0.5,
          max: 2.0,
          divisions: 30,
          activeColor: AppColors.primaryPink,
          onChanged: (v) => onChanged(double.parse(v.toStringAsFixed(2))),
        ),
        Text(
          '${TypingStyle.closest(value).note} · "$sample" 입력 중 약 ${seconds.toStringAsFixed(1)}초',
          style: AppTextStyles.messageTime.copyWith(height: 1.4),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.myBubble : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primaryPink : AppColors.borderLight),
        ),
        child: Text(label, style: AppTextStyles.choiceButton.copyWith(fontSize: 13)),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.myBubble : AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: selected ? AppColors.primaryPink : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.primaryPink : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.choiceButton),
            Text(note, style: AppTextStyles.messageTime),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, required this.hint, this.lines = 1});

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppTextStyles.speakerName),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 4,
            decoration: InputDecoration(hintText: hint, hintMaxLines: 3),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.chatBubbleBody)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: AppTextStyles.appBarTitle)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// 만든 대본 미리보기 + 내 캐릭터에 추가
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.bundle,
    required this.warnings,
    required this.onAdd,
    this.onExport,
  });

  final ScenarioBundle bundle;
  final List<String> warnings;
  final VoidCallback onAdd;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final c = bundle.character;
    final byStage = {
      for (final s in c.affectionStages)
        s.stageLabel: bundle.events.where((e) => e.stageLabel == s.stageLabel && !e.isEnding).toList(),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.primaryPink.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${c.name} 준비 완료', style: AppTextStyles.appBarTitle),
          const SizedBox(height: 4),
          Text(ScenarioSummary.of(bundle).line, style: AppTextStyles.messageTime.copyWith(height: 1.4)),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in byStage.entries)
            if (entry.value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${entry.key}: ${entry.value.map((e) => e.isDaily ? '(일상) ${e.title}' : e.title).join(', ')}',
                  style: AppTextStyles.systemNotice,
                ),
              ),
          if (warnings.isNotEmpty) ProblemList(title: '확인해 보면 좋은 점', items: warnings),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton(onPressed: onAdd, child: const Text('내 캐릭터에 추가')),
          if (onExport != null) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('엑셀로 내보내서 고치기'),
              onPressed: onExport,
            ),
          ],
        ],
      ),
    );
  }
}
