import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart' as database;
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

final Provider<ForumDraftRepository> forumDraftRepositoryProvider =
    Provider<ForumDraftRepository>(
        (Ref ref) => ForumDraftRepository(
            ref.watch(database.appDatabaseProvider),
            ref.watch(forumClientProvider),
            ref.watch(authControllerProvider).value?.userId ?? 0,
        ),
    );

class ForumDraftRepository
{
    ForumDraftRepository(this._database, this._client, this._userId);

    final database.AppDatabase _database;
    final ForumClient _client;
    final int _userId;

    Future<void> save(String draftId, ForumActionDraft draft)
    {
        final String id = _draftId(draftId);
        _requireCurrentUser(draft.userId);
        final String valuesJson = jsonEncode(draft.values);
        return _withActiveAccount(() => _database
            .into(_database.forumDrafts)
            .insertOnConflictUpdate(database.ForumDraftsCompanion.insert(
                draftId: id,
                accountKey: _accountKey,
                action: draft.kind.name,
                fid: Value<int?>(draft.target.boardId),
                tid: Value<int?>(draft.target.threadId),
                pid: Value<int?>(draft.target.postId),
                subject: draft.values['subject']?.firstOrNull ?? '',
                message: draft.values['message']?.firstOrNull ?? '',
                // V2 尚未发布，复用现有 JSON 载荷列保存全部动态用户字段；
                // formhash / 验证码已由 ForumActionDraft 在进入仓库前拒绝。
                attachmentsJson: valuesJson,
                updatedAt: draft.updatedAt,
            )));
    }

    Future<ForumActionDraft?> load(String draftId)
    {
        final String id = _draftId(draftId);
        return _withActiveAccount(() async
        {
            final database.ForumDraft? row =
                await (_database.select(_database.forumDrafts)..where(
                    (database.ForumDrafts table) =>
                        table.accountKey.equals(_accountKey) &
                        table.draftId.equals(id),
                )).getSingleOrNull();
            return row == null ? null : _decode(row);
        });
    }

    Future<List<ForumActionDraft>> list()
    {
        return _withActiveAccount(() async
        {
            final List<database.ForumDraft> rows =
                await (_database.select(_database.forumDrafts)
                    ..where((database.ForumDrafts table) =>
                        table.accountKey.equals(_accountKey))
                    ..orderBy(<OrderClauseGenerator<database.ForumDrafts>>[
                        (database.ForumDrafts table) =>
                            OrderingTerm.desc(table.updatedAt),
                    ])).get();
            return rows
                .map(_decode)
                .whereType<ForumActionDraft>()
                .toList(growable: false);
        });
    }

    Future<void> delete(String draftId, {required int userId})
    {
        final String id = _draftId(draftId);
        _requireCurrentUser(userId);
        return _withActiveAccount(() =>
            (_database.delete(_database.forumDrafts)..where(
                (database.ForumDrafts table) =>
                    table.accountKey.equals(_accountKey) &
                    table.draftId.equals(id),
            )).go());
    }

    ForumActionDraft? _decode(database.ForumDraft row)
    {
        try
        {
            final ForumActionKind kind = ForumActionKind.values.byName(
                row.action,
            );
            final Object? decoded = jsonDecode(row.attachmentsJson);
            if (decoded is! Map)
            {
                return null;
            }
            final Map<String, List<String>> values = <String, List<String>>{
                for (final MapEntry<Object?, Object?> entry in decoded.entries)
                    if (entry.key is String && entry.value is List)
                        entry.key as String: (entry.value as List)
                            .map((Object? value) => value?.toString() ?? '')
                            .toList(growable: false),
            };
            return ForumActionDraft(
                userId: _userId,
                kind: kind,
                target: ForumActionTarget(
                    boardId: row.fid,
                    threadId: row.tid,
                    postId: row.pid,
                ),
                values: values,
                updatedAt: row.updatedAt,
            );
        }
        on Object
        {
            return null;
        }
    }

    Future<T> _withActiveAccount<T>(Future<T> Function() operation)
    {
        _requireCurrentUser(_userId);
        return _client.withActiveAccount<T>(_userId, operation);
    }

    String get _accountKey => 'uid:$_userId';

    String _draftId(String value)
    {
        final String id = value.trim();
        if (id.isEmpty || id.length > 160)
        {
            throw ArgumentError.value(value, 'draftId', '草稿标识无效');
        }
        return id;
    }

    void _requireCurrentUser(int userId)
    {
        if (_userId <= 0 || userId != _userId)
        {
            throw StateError('论坛草稿不属于当前账号');
        }
    }
}
