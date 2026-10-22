import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/mallangtalk_models.dart';
import '../../shared/utils/file_io.dart';
import '../../shared/widgets/character_avatar.dart';
import '../chat/chat_notifier.dart';
import '../library/character_library.dart';
import '../studio/character_import.dart';
import '../studio/script_workbook.dart';

/// [초보자 노트] '내 캐릭터' 탭: 받아오거나 만든 캐릭터 목록. 누르면 프로필이 뜨고 거기서 1:1 채팅을 시작합니다.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(characterLibraryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('내 캐릭터 ${entries.length}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
          child: entries.isEmpty
              ? _EmptyFriends(onAdd: () => context.go('/add'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final c = entry.bundle.character;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 4),
                      leading: CharacterAvatar(character: c, radius: 24),
                      title: Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
                      subtitle: Text(
                        c.statusMessage.isEmpty ? entry.sourceLabel : c.statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.systemNotice,
                      ),
                      trailing: Text(entry.sourceLabel, style: AppTextStyles.messageTime),
                      onTap: () => showCharacterProfile(context, entry),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_add_alt_1_rounded, size: 48, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          const Text('아직 캐릭터가 없어요', style: AppTextStyles.appBarTitle),
          const SizedBox(height: 6),
          const Text(
            '캐릭터를 받아오거나 직접 만들어 보세요',
            style: AppTextStyles.systemNotice,
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(onPressed: onAdd, child: const Text('캐릭터 추가하러 가기')),
        ],
      ),
    );
  }
}

/// 캐릭터 프로필 (1:1 채팅, 앨범, 내보내기, 다시 하기, 삭제)
Future<void> showCharacterProfile(BuildContext context, LibraryEntry entry) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _CharacterProfileSheet(entry: entry, parentContext: context),
  );
}

class _CharacterProfileSheet extends ConsumerWidget {
  const _CharacterProfileSheet({required this.entry, required this.parentContext});

  final LibraryEntry entry;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = entry.bundle;
    final c = bundle.character;
    final summary = ScenarioSummary.of(bundle);
    final messenger = ScaffoldMessenger.of(parentContext);
    final router = GoRouter.of(parentContext);

    void close() => Navigator.of(context).pop();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: CharacterAvatar(character: c, radius: 40)),
            const SizedBox(height: AppSpacing.md),
            Text(c.name, textAlign: TextAlign.center, style: AppTextStyles.appBarTitle.copyWith(fontSize: 20)),
            if (c.statusMessage.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(c.statusMessage, textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(summary.line, textAlign: TextAlign.center, style: AppTextStyles.messageTime.copyWith(height: 1.4)),
            const SizedBox(height: 6),
            Text(
              '타자 스타일: ${TypingStyle.closest(c.typingSpeedMultiplier).label}',
              textAlign: TextAlign.center,
              style: AppTextStyles.messageTime,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: const Text('1:1 채팅'),
              onPressed: () {
                close();
                ref.read(chatRoomsProvider.notifier).open(c.id);
                router.push('/chat/${c.id}');
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('앨범'),
                    onPressed: () {
                      close();
                      router.push('/chat/${c.id}/album');
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('처음부터'),
                    onPressed: () {
                      close();
                      ref.read(chatRoomProvider(c.id).notifier).restart();
                      messenger.showSnackBar(
                        SnackBar(content: Text('${c.name}와의 대화를 처음부터 시작했어요 (앨범은 그대로)')),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('엑셀로 내보내기'),
                    onPressed: () async {
                      await FileIO.save(
                        fileName: '${FileIO.safeName(c.name)}_대본.xlsx',
                        bytes: ScriptWorkbook.encode(bundle),
                        mimeType: FileIO.xlsxMime,
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('캐릭터 파일'),
                    onPressed: () async {
                      await FileIO.save(
                        fileName: '${FileIO.safeName(c.name)}.json',
                        bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(bundle.toJson())),
                        mimeType: FileIO.jsonMime,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryPink),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text('${c.name} 삭제'),
                    content: const Text('대화 기록과 앨범도 함께 지워져요. 되돌릴 수 없어요.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                if (context.mounted) close();
                ref.read(chatRoomsProvider.notifier).leave(c.id);
                await ref.read(characterLibraryProvider.notifier).remove(c.id);
                ref.invalidate(chatRoomProvider(c.id));
                messenger.showSnackBar(SnackBar(content: Text('${c.name}을(를) 지웠어요')));
              },
              child: const Text('캐릭터 삭제'),
            ),
          ],
        ),
      ),
    );
  }
}
