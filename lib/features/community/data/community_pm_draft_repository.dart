import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart' as database;
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';

final Provider<CommunityPmDraftRepository> communityPmDraftRepositoryProvider =
    Provider<CommunityPmDraftRepository>(
      (Ref ref) => CommunityPmDraftRepository(
        ref.watch(database.appDatabaseProvider),
        ref.watch(forumClientProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
      ),
    );

class CommunityPmDraftRepository {
  CommunityPmDraftRepository(this._database, this._client, this._userId);

  final database.AppDatabase _database;
  final ForumClient _client;
  final int _userId;

  Future<void> save(String draftId, CommunityPmDraft draft) {
    final String id = _validDraftId(draftId);
    _validateDraft(draft);
    return _client.withActiveAccount<void>(
      _userId,
      () => _database.into(_database.forumDrafts).insertOnConflictUpdate(
            database.ForumDraftsCompanion.insert(
              draftId: id,
              accountKey: _accountKey,
              action: 'communityPm:${draft.context.name}',
              fid: const Value<int?>.absent(),
              tid: Value<int?>(draft.peerUserId > 0 ? draft.peerUserId : null),
              pid: const Value<int?>.absent(),
              subject: draft.username,
              message: draft.message,
              attachmentsJson: '{}',
              updatedAt: draft.updatedAt,
            ),
          ),
    );
  }

  Future<CommunityPmDraft?> load(String draftId) {
    final String id = _validDraftId(draftId);
    _checkUser();
    return _client.withActiveAccount<CommunityPmDraft?>(_userId, () async {
      final database.ForumDraft? row =
          await (_database.select(_database.forumDrafts)..where(
                (database.ForumDrafts table) =>
                    table.accountKey.equals(_accountKey) &
                    table.draftId.equals(id),
              ))
              .getSingleOrNull();
      if (row == null || !row.action.startsWith('communityPm:')) {
        return null;
      }
      try {
        final CommunityPmSendContext context =
            CommunityPmSendContext.values.byName(
          row.action.substring('communityPm:'.length),
        );
        return CommunityPmDraft(
          userId: _userId,
          context: context,
          peerUserId: row.tid ?? 0,
          username: row.subject,
          message: row.message,
          updatedAt: row.updatedAt,
        );
      } on Object {
        return null;
      }
    });
  }

  Future<void> delete(String draftId) {
    final String id = _validDraftId(draftId);
    _checkUser();
    return _client.withActiveAccount<void>(
      _userId,
      () => (_database.delete(_database.forumDrafts)..where(
            (database.ForumDrafts table) =>
                table.accountKey.equals(_accountKey) &
                table.draftId.equals(id),
          )).go(),
    );
  }

  void _validateDraft(CommunityPmDraft draft) {
    _checkUser();
    if (draft.userId != _userId ||
        (draft.context == CommunityPmSendContext.conversation &&
            draft.peerUserId <= 0) ||
        (draft.context == CommunityPmSendContext.compose &&
            draft.peerUserId != 0)) {
      throw StateError('私信草稿不属于当前账号或目标');
    }
  }

  void _checkUser() {
    if (_userId <= 0) {
      throw StateError('私信草稿缺少当前账号');
    }
  }

  String _validDraftId(String value) {
    final String result = value.trim();
    if (result.isEmpty || result.length > 160) {
      throw ArgumentError.value(value, 'draftId', '私信草稿标识无效');
    }
    return result;
  }

  String get _accountKey => 'uid:$_userId';
}
