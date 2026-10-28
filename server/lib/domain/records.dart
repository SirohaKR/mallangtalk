/// 로그인한 유저
class UserRecord {
  final int id;
  final String username;
  final String nickname;

  /// 제작자 프로필 사진 (/api/images/… 주소, 안 올렸으면 빈 글자)
  final String avatarUrl;

  /// 제작자 한줄 소개
  final String intro;
  const UserRecord(this.id, this.username, this.nickname,
      {this.avatarUrl = '', this.intro = ''});

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'intro': intro,
      };
}

/// 서버에 저장된 캐릭터 하나 (bundle은 앱의 캐릭터 파일 JSON 그대로)
class CharacterRecord {
  final String id;
  final int ownerId;
  final String ownerNickname;

  /// 제작자 프로필 사진·한줄 소개 (말랑이 찾기 카드와 제작자 프로필에 보임)
  final String ownerAvatar;
  final String ownerIntro;
  final bool published;
  final DateTime createdAt;

  /// 이 캐릭터를 친구로 추가한 사람 수 (말랑이 찾기 '인기' 정렬)
  final int friendCount;
  final String bundleJson;
  final DateTime updatedAt;
  const CharacterRecord(this.id, this.ownerId, this.ownerNickname,
      this.published, this.bundleJson, this.updatedAt,
      {DateTime? createdAt,
      this.friendCount = 0,
      this.ownerAvatar = '',
      this.ownerIntro = ''})
      : createdAt = createdAt ?? updatedAt;
}
