import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import 'state_sync.dart';

/// [초보자 노트] 기기 연동 중 한쪽 값으로 덮으면 다른 쪽 데이터가 크게 사라지는 항목이 있을 때 뜨는 화면이에요.
/// 고르기 전에는 앱을 열지 않아서, 그 사이에 아무것도 덮이지 않아요.
/// (2026-11-02 PC로 접속했다가 폰 데이터가 사라진 일 뒤에 추가)
class SyncConflictScreen extends ConsumerStatefulWidget {
  const SyncConflictScreen({super.key, required this.conflicts});

  final List<SyncConflict> conflicts;

  @override
  ConsumerState<SyncConflictScreen> createState() => _SyncConflictScreenState();
}

class _SyncConflictScreenState extends ConsumerState<SyncConflictScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _resolve(bool keepBigger) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(resolveSyncConflictsProvider)(widget.conflicts, keepBigger: keepBigger);
    } catch (e) {
      if (mounted) setState(() => _error = '서버에 저장하지 못했어요. 인터넷을 확인하고 다시 눌러 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = {for (final c in widget.conflicts) c.label}.toList();
    final localMore = widget.conflicts.any((c) => c.localBigger);
    return Scaffold(
      backgroundColor: AppColors.chatRoomBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.sync_problem_rounded, size: 48, color: AppColors.primaryPink),
                  const SizedBox(height: 16),
                  Text(
                    localMore ? '이 기기에 있는 데이터가 서버보다 많아요' : '서버에 있는 데이터가 이 기기보다 많아요',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.systemNotice.copyWith(
                        fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '다른 기기와 맞추면 ${labels.join('·')}이(가) 비거나 크게 줄어들어요.\n'
                    '실수로 덮인 것 같으면 데이터가 많은 쪽을 지켜 주세요.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.systemNotice.copyWith(color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('sync_keep_bigger'),
                    onPressed: _busy ? null : () => _resolve(true),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryPink, minimumSize: const Size.fromHeight(48)),
                    child: const Text('데이터 많은 쪽 지키기 (추천)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('sync_follow_newer'),
                    onPressed: _busy ? null : () => _resolve(false),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('최근에 바뀐 쪽 쓰기 (일부러 지웠어요)'),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.systemNotice.copyWith(color: AppColors.primaryPink)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
