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
import '../../shared/widgets/character_sheet_view.dart';
import '../chat/chat_notifier.dart';
import '../chat/start_chat.dart';
import '../library/character_library.dart';
import '../settings/user_profile.dart';
import '../../shared/utils/korean.dart';

/// [초보자 노트] '내 캐릭터' 탭은 카톡 친구창처럼: 맨 위 내 프로필, 그 아래 즐겨찾기, 그 아래 캐릭터 목록.
/// 캐릭터를 누르면 프로필이 뜨고, 거기서 1:1 채팅·즐겨찾기를 해요.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(characterLibraryProvider);
    final favorites = ref.watch(favoritesProvider);
    final starred = entries.where((e) => favorites.contains(e.id)).toList();
    final others = entries.where((e) => !favorites.contains(e.id)).toList();

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 4),
          child: Text(title, style: AppTextStyles.messageTime),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('말랑')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.mobileMaxWidth),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              const _MyProfileTile(),
              const Divider(height: 1),
              if (entries.isEmpty) _EmptyFriends(onAdd: () => context.go('/add')),
              if (starred.isNotEmpty) ...[
                section('즐겨찾기 ${starred.length}'),
                for (final e in starred) _FriendTile(entry: e),
              ],
              if (others.isNotEmpty) ...[
                section('친구 ${entries.length}'),
                for (final e in others) _FriendTile(entry: e),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = entry.bundle.character;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
      leading: CharacterAvatar(character: c, radius: 24),
      title: Text(c.name, style: AppTextStyles.appBarTitle.copyWith(fontSize: 15)),
      subtitle: Text(
        c.statusMessage.isEmpty ? entry.sourceLabel : CharacterModel.fillUserName(c.statusMessage, '너', charName: c.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.systemNotice,
      ),
      trailing: Text(entry.sourceLabel, style: AppTextStyles.messageTime),
      onTap: () => showCharacterProfile(context, entry),
    );
  }
}

/// 친구창 맨 위 내 프로필. 누르면 사진·별명·한줄 소개를 고침
class _MyProfileTile extends ConsumerWidget {
  const _MyProfileTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      leading: MyProfileAvatar(url: profile.avatarUrl, radius: 30),
      title: Text(
        profile.hasNickname ? profile.nickname : '내 프로필',
        style: AppTextStyles.appBarTitle.copyWith(fontSize: 17),
      ),
      subtitle: Text(
        profile.intro.isEmpty ? '눌러서 사진과 소개를 정해요' : profile.intro,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.systemNotice,
      ),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surfaceWhite,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => const _MyProfileEditor(),
      ),
    );
  }
}

/// 내 프로필 사진 (없으면 기본 사람 아이콘)
class MyProfileAvatar extends StatelessWidget {
  const MyProfileAvatar({super.key, required this.url, this.radius = 24});

  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = CharacterImage.providerFor(url);
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.borderLight,
      backgroundImage: image,
      child: image == null ? Icon(Icons.person_rounded, size: radius, color: AppColors.surfaceWhite) : null,
    );
  }
}

class _MyProfileEditor extends ConsumerStatefulWidget {
  const _MyProfileEditor();

  @override
  ConsumerState<_MyProfileEditor> createState() => _MyProfileEditorState();
}

class _MyProfileEditorState extends ConsumerState<_MyProfileEditor> {
  late final _profile = ref.read(userProfileProvider);
  late final _nickname = TextEditingController(text: _profile.nickname);
  late final _intro = TextEditingController(text: _profile.intro);
  late final _persona = TextEditingController(text: _profile.persona);
  late String _avatar = _profile.avatarUrl;

  @override
  void dispose() {
    _nickname.dispose();
    _intro.dispose();
    _persona.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final image = await pickProfileImage();
                  if (image != null) setState(() => _avatar = image);
                },
                child: Stack(
                  children: [
                    MyProfileAvatar(url: _avatar, radius: 40),
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.primaryPink,
                        child: Icon(Icons.photo_camera_rounded, size: 15, color: AppColors.surfaceWhite),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nickname,
              maxLength: 12,
              decoration: const InputDecoration(labelText: '기본 별명', hintText: '캐릭터가 나를 부를 이름'),
            ),
            TextField(
              controller: _intro,
              maxLength: 60,
              decoration: const InputDecoration(labelText: '한줄 소개', hintText: 'AI 자유대화에서 캐릭터가 참고해요'),
            ),
            TextField(
              controller: _persona,
              minLines: 2,
              maxLines: 5,
              maxLength: 400,
              decoration: const InputDecoration(
                labelText: '기본 페르소나',
                alignLabelWithHint: true,
                hintText: '대화 속 나의 설정 (나이·성격·외모·상황). 캐릭터마다 대화 시작할 때 바꿀 수 있어요',
                hintMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
              onPressed: () async {
                await ref
                    .read(userProfileProvider.notifier)
                    .save(nickname: _nickname.text, intro: _intro.text, avatarUrl: _avatar, persona: _persona.text);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('저장'),
            ),
          ],
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
/// 시트는 끌어 올리면 커지고, 맨 위에서 아래로 밀면 닫혀요 (폰에서 내용이 길어도 스크롤과 안 엉키게)
/// [inChat]: 그 캐릭터 대화방에서 열었으면 '1:1 채팅'은 시트만 닫음
Future<void> showCharacterProfile(BuildContext context, LibraryEntry entry, {bool inChat = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 1,
      snap: true,
      builder: (_, scrollController) => _CharacterProfileSheet(
        entry: entry,
        parentContext: context,
        scrollController: scrollController,
        inChat: inChat,
      ),
    ),
  );
}

class _CharacterProfileSheet extends ConsumerWidget {
  const _CharacterProfileSheet({
    required this.entry,
    required this.parentContext,
    required this.scrollController,
    this.inChat = false,
  });

  final LibraryEntry entry;
  final BuildContext parentContext;
  final ScrollController scrollController;
  final bool inChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = entry.bundle;
    final c = bundle.character;
    final messenger = ScaffoldMessenger.of(parentContext);
    final router = GoRouter.of(parentContext);

    void close() => Navigator.of(context).pop();

    return SafeArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      key: const ValueKey('profile_photo'),
                      onTap: () => showCharacterPhoto(context, c),
                      child: CharacterAvatar(character: c, radius: 40),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: ref.watch(favoritesProvider).contains(c.id) ? '즐겨찾기 빼기' : '즐겨찾기',
                  onPressed: () => ref.read(favoritesProvider.notifier).toggle(c.id),
                  icon: Icon(
                    ref.watch(favoritesProvider).contains(c.id) ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppColors.primaryPink,
                    size: 28,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(c.name, textAlign: TextAlign.center, style: AppTextStyles.appBarTitle.copyWith(fontSize: 20)),
            if (c.statusMessage.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(CharacterModel.fillUserName(c.statusMessage, '너', charName: c.name), textAlign: TextAlign.center, style: AppTextStyles.systemNotice),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: const Text('1:1 채팅'),
              onPressed: () {
                close();
                if (!inChat) openChat(parentContext, c);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('앨범', maxLines: 1)),
                    onPressed: () {
                      close();
                      router.push('/chat/${c.id}/album');
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.speed_rounded, size: 18),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('대화 속도', maxLines: 1)),
                    onPressed: () {
                      close();
                      pickChatTempo(parentContext, c);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('처음부터', maxLines: 1)),
                    onPressed: () {
                      close();
                      ref.read(chatRoomProvider(c.id).notifier).restart();
                      messenger.showSnackBar(
                        SnackBar(content: Text('${josa(c.name, '과', '와')}의 대화를 처음부터 시작했어요 (앨범은 그대로)')),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (entry.source != CharacterSource.builtin) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('고치기'),
                      onPressed: () {
                        close();
                        router.push('/edit/${c.id}');
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
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
            const SizedBox(height: AppSpacing.lg),
            CharacterSheetView(character: c, nickname: ref.watch(chatNicknameProvider(c.id))),
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
                messenger.showSnackBar(SnackBar(content: Text('${josa(c.name, '을', '를')} 지웠어요')));
              },
              child: const Text('캐릭터 삭제'),
            ),
          ],
        ),
      ),
    );
  }
}
