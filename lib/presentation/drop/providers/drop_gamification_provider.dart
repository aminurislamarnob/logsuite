import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../models/drop_gamification.dart';
import '../services/drop_gamification_service.dart';

final dropGamificationServiceProvider = Provider<DropGamificationService>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return DropGamificationService(prefs);
});

final dropGamificationProvider =
    StateNotifierProvider<DropGamificationNotifier, DropGamificationStats>((ref) {
  final service = ref.watch(dropGamificationServiceProvider);
  return DropGamificationNotifier(service);
});

class DropGamificationNotifier extends StateNotifier<DropGamificationStats> {
  final DropGamificationService _service;

  DropGamificationNotifier(this._service) : super(_service.getStats());

  void refresh() {
    state = _service.getStats();
  }

  Future<GamificationReward> recordDropCaptured({bool hasTags = false}) async {
    final reward = await _service.recordDropCaptured(hasTags: hasTags);
    state = _service.getStats();
    return reward;
  }

  Future<GamificationReward> recordDropTriaged({bool reachedInboxZero = false}) async {
    final reward = await _service.recordDropTriaged(reachedInboxZero: reachedInboxZero);
    state = _service.getStats();
    return reward;
  }

  Future<GamificationReward> recordBulkTriaged(int count) async {
    final reward = await _service.recordBulkTriaged(count);
    state = _service.getStats();
    return reward;
  }

  Future<GamificationReward> recordConvertedToNote() async {
    final reward = await _service.recordConvertedToNote();
    state = _service.getStats();
    return reward;
  }

  Future<GamificationReward> recordConvertedToTask() async {
    final reward = await _service.recordConvertedToTask();
    state = _service.getStats();
    return reward;
  }

  Future<GamificationReward> recordDropFavorited() async {
    final reward = await _service.recordDropFavorited();
    state = _service.getStats();
    return reward;
  }
}
