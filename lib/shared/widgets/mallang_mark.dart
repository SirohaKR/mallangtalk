import 'package:flutter/material.dart';

/// [초보자 노트] 말랑톡 마스코트 '말랑'(몸 전체 실루엣)을 코드로 그리는 위젯입니다.
/// 원본 그림은 assets/branding/mallang_character.svg 이고, 같은 좌표(100×100)를 그대로 옮겼어요.
/// 이미지 파일이 아니라서 아래 탭처럼 작은 크기에서도 선명하고, 색을 마음대로 바꿀 수 있어요.
/// plus를 켜면 오른쪽 위에 +가 붙은 '말랑이+' 모양이 돼요 (말랑이 찾기 탭).
class MallangMark extends StatelessWidget {
  const MallangMark({super.key, this.size = 24, this.color, this.eyeColor = Colors.white, this.plus = false});

  final double size;

  /// 몸 색. 비워 두면 주변 아이콘 색(IconTheme)을 따라가요.
  final Color? color;
  final Color eyeColor;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    final body = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MallangPainter(body, eyeColor, plus)),
    );
  }
}

class _MallangPainter extends CustomPainter {
  _MallangPainter(this.body, this.eye, this.plus);

  final Color body;
  final Color eye;
  final bool plus;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    if (plus) {
      // 오른쪽 위에 + 를 그리고, 몸은 조금 줄여서 왼쪽 아래로
      final p = Paint()
        ..color = body
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(84, 8), const Offset(84, 34), p);
      canvas.drawLine(const Offset(71, 21), const Offset(97, 21), p);
      canvas.translate(-4, 18);
      canvas.scale(0.82);
    }
    canvas.translate(0, -3);
    final b = Paint()..color = body;
    for (final (x, y, r) in const [(37.0, 38.0, 18.0), (63.0, 38.0, 18.0), (50.0, 52.0, 26.0), (22.0, 66.0, 15.0), (78.0, 66.0, 15.0)]) {
      canvas.drawCircle(Offset(x, y), r, b);
    }
    canvas.drawRRect(RRect.fromLTRBR(12, 62, 88, 86, const Radius.circular(12)), b);
    final e = Paint()..color = eye;
    for (final x in const [41.0, 59.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 58), width: 7.6, height: 15), e);
    }
  }

  @override
  bool shouldRepaint(_MallangPainter old) => old.body != body || old.eye != eye || old.plus != plus;
}
