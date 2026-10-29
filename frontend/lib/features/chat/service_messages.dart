import 'dart:math';

import '../../shared/models/mallangtalk_models.dart';

/// [초보자 노트] 서비스 말랑이(운세·행운의 편지처럼 정해진 때 먼저 톡을 보내는 캐릭터)의 문구 만들기.
/// 화면과 상관없는 계산만 모아 둬서 테스트하기 쉽게 했어요. AI 모드는 대화방 쪽에서 AI를 불러요.

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// [since] 다음부터 [now]까지 보낼 시각들 (요일·시각이 맞는 것, 오래된 순, 많으면 최근 [max]개만)
List<DateTime> dueServiceSlots(ServiceConfig config, DateTime since, DateTime now, {int max = 7}) {
  final times = [
    for (final t in config.times)
      if (_parseTime(t) case final parsed?) parsed,
  ];
  if (times.isEmpty || config.days.isEmpty || !now.isAfter(since)) return const [];
  final slots = <DateTime>[];
  // 너무 오래 안 열었으면 최근 며칠만 봄
  var day = DateTime(since.year, since.month, since.day);
  final oldest = DateTime(now.year, now.month, now.day).subtract(Duration(days: max + 1));
  if (day.isBefore(oldest)) day = oldest;
  while (!day.isAfter(now)) {
    if (config.days.contains(day.weekday)) {
      for (final (h, m) in times) {
        final slot = DateTime(day.year, day.month, day.day, h, m);
        if (slot.isAfter(since) && !slot.isAfter(now)) slots.add(slot);
      }
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  slots.sort();
  return slots.length > max ? slots.sublist(slots.length - max) : slots;
}

(int, int)? _parseTime(String t) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return (h, min);
}

/// '오전 8:00' 같은 화면용 시각
String serviceTimeLabel(String t) {
  final parsed = _parseTime(t);
  if (parsed == null) return t;
  final (h, m) = parsed;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${h < 12 ? '오전' : '오후'} $h12:${m.toString().padLeft(2, '0')}';
}

/// '매일 오전 8:00' / '월·수·금 오전 8:00, 오후 9:00' 같은 보내는 때 설명
String serviceScheduleLabel(ServiceConfig c) {
  final days = [...c.days]..sort();
  final dayText = days.length == 7
      ? '매일'
      : days.length == 5 && !days.contains(6) && !days.contains(7)
          ? '평일'
          : days.length == 2 && days.contains(6) && days.contains(7)
              ? '주말'
              : days.map((d) => _weekdays[d - 1]).join('·');
  return '$dayText ${c.times.map(serviceTimeLabel).join(', ')}';
}

/// 만든 문구 한 개와, 같은 문구가 다시 안 나오게 기억할 표시
typedef ServiceMessage = ({String text, String key});

/// 목록·표 모드의 문구 하나 (AI 모드거나 쓸 문구가 없으면 null).
/// [used]: 이번 바퀴에 이미 쓴 표시들 (noRepeat일 때 피함, 다 썼으면 처음부터)
ServiceMessage? composeServiceMessage(
  ServiceConfig config, {
  required String userName,
  required String charName,
  required DateTime now,
  required Random random,
  Set<String> used = const {},
  Map<String, String> userInfo = const {},
}) {
  final info = {
    for (final e in userInfo.entries)
      if (e.value.trim().isNotEmpty) e.key.trim(): e.value.trim()
  };
  switch (config.mode) {
    case 'list':
      final lines = [
        for (final l in config.lines)
          if (l.trim().isNotEmpty) l.trim()
      ];
      if (lines.isEmpty) return null;
      final i = _pick([for (var j = 0; j < lines.length; j++) j], config.noRepeat ? used : const {}, random);
      return (
        text: fillServiceTemplate(lines[i], info, userName: userName, charName: charName, now: now, random: random),
        key: 'l$i'
      );
    case 'table':
      if (config.rows.isEmpty || config.template.trim().isEmpty) return null;
      final i = _pick(matchingServiceRows(config, info), config.noRepeat ? used : const {}, random);
      final row = config.rows[i];
      final values = {
        ...info,
        for (var c = 0; c < config.columns.length; c++) config.columns[c].trim(): c < row.length ? row[c] : '',
      };
      return (
        text: fillServiceTemplate(config.template, values,
            userName: userName, charName: charName, now: now, random: random),
        key: 'r$i'
      );
    default:
      return null;
  }
}

/// 표에서 고를 수 있는 줄: 유저가 알려 준 정보(띠 등)와 같은 이름의 칸이 있으면 값이 맞는 줄만.
/// 맞는 줄이 없으면 전체
List<int> matchingServiceRows(ServiceConfig config, Map<String, String> userInfo) {
  final all = [for (var i = 0; i < config.rows.length; i++) i];
  var pool = all;
  for (final e in userInfo.entries) {
    final c = config.columns.indexWhere((x) => x.trim() == e.key.trim());
    if (c < 0 || e.value.trim().isEmpty) continue;
    final want = e.value.trim().toLowerCase();
    final hit = [
      for (final i in pool)
        if (c < config.rows[i].length && config.rows[i][c].trim().toLowerCase() == want) i
    ];
    if (hit.isNotEmpty) pool = hit;
  }
  return pool;
}

/// 아직 안 쓴 것 중에서 무작위 (다 썼으면 전체에서)
int _pick(List<int> candidates, Set<String> used, Random random) {
  final fresh = [
    for (final i in candidates)
      if (!used.contains('l$i') && !used.contains('r$i')) i
  ];
  final pool = fresh.isEmpty ? candidates : fresh;
  return pool[random.nextInt(pool.length)];
}

/// 서비스 말랑이가 자주 묻는 정보의 기본 고르기 목록 (데이터 표에 같은 칸이 있으면 표 값이 먼저)
const serviceAskPresets = <String, List<String>>{
  '띠': ['쥐띠', '소띠', '범띠', '토끼띠', '용띠', '뱀띠', '말띠', '양띠', '원숭이띠', '닭띠', '개띠', '돼지띠'],
  '별자리': ['양자리', '황소자리', '쌍둥이자리', '게자리', '사자자리', '처녀자리', '천칭자리', '전갈자리', '사수자리', '염소자리', '물병자리', '물고기자리'],
  '혈액형': ['A형', 'B형', 'O형', 'AB형'],
  'MBTI': [
    'ISTJ',
    'ISFJ',
    'INFJ',
    'INTJ',
    'ISTP',
    'ISFP',
    'INFP',
    'INTP',
    'ESTP',
    'ESFP',
    'ENFP',
    'ENTP',
    'ESTJ',
    'ESFJ',
    'ENFJ',
    'ENTJ'
  ],
};

/// 물어볼 정보 [field]의 고르기 목록 (없으면 직접 적기)
List<String> serviceAskChoices(ServiceConfig config, String field) {
  final fromTable = config.choicesFor(field);
  if (fromTable.isNotEmpty && fromTable.length <= 24) return fromTable;
  return serviceAskPresets[field.trim()] ?? const [];
}

/// 유저 정보를 AI에게 넘길 한 줄로 ('띠: 범띠 / 생일: 3월 2일')
String serviceUserInfoLine(Map<String, String> info) => [
      for (final e in info.entries)
        if (e.value.trim().isNotEmpty) '${e.key.trim()}: ${e.value.trim()}'
    ].join(' / ');

/// 틀의 {칸 이름}을 표 값으로, {이름}·{날짜}·{요일}·{숫자}를 그때 값으로 채움
String fillServiceTemplate(
  String template,
  Map<String, String> values, {
  required String userName,
  required String charName,
  required DateTime now,
  required Random random,
}) {
  final filled = template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) {
    final key = m.group(1)!.trim();
    if (values.containsKey(key)) return values[key]!;
    return switch (key) {
      '날짜' => '${now.month}월 ${now.day}일',
      '요일' => '${_weekdays[now.weekday - 1]}요일',
      '숫자' => '${random.nextInt(45) + 1}',
      _ => m.group(0)!, // {이름} 등은 아래에서 조사까지 맞춰 바꿈
    };
  });
  return CharacterModel.fillUserName(filled, userName, charName: charName);
}

/// 엑셀·시트에서 복사한 표(탭) 또는 CSV(쉼표)를 칸 이름 + 줄들로. 첫 줄이 칸 이름.
/// CSV는 "따옴표로 감싼 칸"(안에 쉼표·줄바꿈·"" 가능)도 읽음
({List<String> columns, List<List<String>> rows}) parseServiceTable(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1); // 엑셀 CSV 맨 앞 BOM
  final firstLine = text.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final sep = firstLine.contains('\t') ? '\t' : ',';
  final records = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.toString().trim().isEmpty) {
      cell.clear();
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) records.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((c) => c.isNotEmpty)) records.add(row);
  if (records.isEmpty) return (columns: const <String>[], rows: const <List<String>>[]);
  return (columns: records.first, rows: records.skip(1).toList());
}
