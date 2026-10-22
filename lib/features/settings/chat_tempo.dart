import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_store.dart';

/// 설정에서 고르는 대화 연출 속도
class ChatTempoOption {
  final String label;
  final String note;
  final double tempo;

  const ChatTempoOption(this.label, this.note, this.tempo);

  static const all = [
    ChatTempoOption('리얼하게', '실제로 사람이 치는 것처럼 기다려요', 1.0),
    ChatTempoOption('조금 빠르게', '입력 중 시간을 절반 정도로 줄여요', 0.55),
    ChatTempoOption('빠르게', '이야기만 빨리 보고 싶을 때', 0.25),
  ];
}

/// [초보자 노트] 캐릭터의 '입력 중...' 시간 전체에 곱하는 배율입니다. (캐릭터별 타자 속도와는 따로)
class ChatTempoNotifier extends Notifier<double> {
  @override
  double build() => ref.watch(localStoreProvider).chatTempo ?? 1.0;

  Future<void> set(double tempo) async {
    state = tempo;
    await ref.read(localStoreProvider).saveChatTempo(tempo);
  }
}

final chatTempoProvider = NotifierProvider<ChatTempoNotifier, double>(ChatTempoNotifier.new);
