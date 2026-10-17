import 'package:flutter_riverpod/flutter_riverpod.dart';

final NotifierProvider<FavoriteChanges, int> favoriteChangesProvider =
    NotifierProvider<FavoriteChanges, int>(FavoriteChanges.new);

class FavoriteChanges extends Notifier<int> {
  @override
  int build() => 0;

  void markChanged() {
    state++;
  }
}
