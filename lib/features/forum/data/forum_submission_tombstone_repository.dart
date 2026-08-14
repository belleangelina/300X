import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart' as database;
import 'package:x300/features/forum/domain/forum_action_models.dart';

class SubmissionTombstoneKey {
  const SubmissionTombstoneKey({
    required this.action,
    required this.draftContext,
    this.boardId,
    this.threadId,
    this.postId,
    this.favoriteId,
  });

  final String action;
  final String draftContext;
  final int? boardId;
  final int? threadId;
  final int? postId;
  final int? favoriteId;
}

class SubmissionTombstoneRecord {
  const SubmissionTombstoneRecord({
    required this.attemptId,
    required this.userId,
    required this.key,
    required this.status,
    required this.recordedAt,
  });

  final String attemptId;
  final int userId;
  final SubmissionTombstoneKey key;
  final ForumSubmissionTombstoneStatus status;
  final DateTime recordedAt;
}

class ForumSubmissionBlockedException extends ForumException {
  const ForumSubmissionBlockedException(this.submission)
    : super('检测到该操作有结果未知、尚未人工核对的提交记录；请先回读目标资源，勿重复提交');

  final ForumUnresolvedSubmission submission;
}

class ForumSubmissionTombstoneRepository {
  ForumSubmissionTombstoneRepository(this._database);

  final database.AppDatabase _database;
  final Random _random = Random.secure();
  int _sequence = 0;

  Future<SubmissionTombstoneRecord?> findKey({
    required int userId,
    required SubmissionTombstoneKey key,
  }) async {
    final database.ForumActionTombstone? row =
        await (_database.select(_database.forumActionTombstones)..where(
              (database.ForumActionTombstones table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.contextKey.equals(_contextKeyFor(key)),
            ))
            .getSingleOrNull();
    return row == null ? null : _decodeKey(row, userId);
  }

  Future<String?> claimKey({
    required int userId,
    required SubmissionTombstoneKey key,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final String attemptId = _attemptIdFor(userId, key.action, now);
    final database.ForumActionTombstone? inserted = await _database
        .into(_database.forumActionTombstones)
        .insertReturningOrNull(
          database.ForumActionTombstonesCompanion.insert(
            accountKey: _accountKey(userId),
            contextKey: _contextKeyFor(key),
            attemptId: attemptId,
            action: key.action,
            fid: Value<int?>(key.boardId),
            tid: Value<int?>(key.threadId),
            pid: Value<int?>(key.postId),
            favoriteId: Value<int?>(key.favoriteId),
            draftContext: key.draftContext,
            status: ForumSubmissionTombstoneStatus.pending.name,
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return inserted == null ? null : attemptId;
  }

  Future<String?> claimAttemptedKey({
    required int userId,
    required SubmissionTombstoneKey key,
    required bool deleteDraft,
  }) {
    return _database.transaction<String?>(() async {
      final DateTime now = DateTime.now().toUtc();
      final String attemptId = _attemptIdFor(userId, key.action, now);
      final database.ForumActionTombstone? inserted = await _database
          .into(_database.forumActionTombstones)
          .insertReturningOrNull(
            database.ForumActionTombstonesCompanion.insert(
              accountKey: _accountKey(userId),
              contextKey: _contextKeyFor(key),
              attemptId: attemptId,
              action: key.action,
              fid: Value<int?>(key.boardId),
              tid: Value<int?>(key.threadId),
              pid: Value<int?>(key.postId),
              favoriteId: Value<int?>(key.favoriteId),
              draftContext: key.draftContext,
              status: ForumSubmissionTombstoneStatus.attempted.name,
              createdAt: now,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      if (inserted == null) {
        return null;
      }
      if (deleteDraft && key.draftContext.isNotEmpty) {
        await (_database.delete(_database.forumDrafts)..where(
              (database.ForumDrafts table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.draftId.equals(key.draftContext),
            ))
            .go();
      }
      return attemptId;
    });
  }

  Future<void> markAttemptedKey({
    required int userId,
    required SubmissionTombstoneKey key,
    required String attemptId,
  }) async {
    final int changed =
        await (_database.update(_database.forumActionTombstones)..where(
              (database.ForumActionTombstones table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.contextKey.equals(_contextKeyFor(key)) &
                  table.attemptId.equals(attemptId) &
                  table.status.equals(
                    ForumSubmissionTombstoneStatus.pending.name,
                  ),
            ))
            .write(
              database.ForumActionTombstonesCompanion(
                status: Value<String>(
                  ForumSubmissionTombstoneStatus.attempted.name,
                ),
                updatedAt: Value<DateTime>(DateTime.now().toUtc()),
              ),
            );
    if (changed != 1) {
      throw StateError('提交封存状态已变化');
    }
  }

  Future<void> resolveTrustedOutcomeKey({
    required int userId,
    required SubmissionTombstoneKey key,
    required String attemptId,
    required bool deleteDraft,
  }) {
    return _database.transaction(() async {
      if (deleteDraft && key.draftContext.isNotEmpty) {
        await (_database.delete(_database.forumDrafts)..where(
              (database.ForumDrafts table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.draftId.equals(key.draftContext),
            ))
            .go();
      }
      final int removed = await _deleteKey(
        userId: userId,
        key: key,
        attemptId: attemptId,
      );
      if (removed != 1) {
        throw StateError('提交封存记录已变化');
      }
    });
  }

  Future<bool> acknowledgeKey(SubmissionTombstoneRecord record) async {
    final int removed = await _deleteKey(
      userId: record.userId,
      key: record.key,
      attemptId: record.attemptId,
    );
    return removed == 1;
  }

  Future<ForumUnresolvedSubmission?> find({
    required int userId,
    required ForumActionRequest request,
    required ForumReadbackDescriptor readback,
    required String draftContext,
  }) async {
    final SubmissionTombstoneRecord? record = await findKey(
      userId: userId,
      key: _forumKey(request, draftContext),
    );
    return record == null ? null : _decode(record, request, readback);
  }

  Future<String?> claim({
    required int userId,
    required ForumPreparedAction prepared,
  }) {
    return claimContext(
      userId: userId,
      request: prepared.request,
      draftContext: prepared.draftContext,
    );
  }

  Future<String?> claimAttempted({
    required int userId,
    required ForumPreparedAction prepared,
  }) {
    return claimAttemptedKey(
      userId: userId,
      key: _forumKey(prepared.request, prepared.draftContext),
      deleteDraft: false,
    );
  }

  Future<String?> claimContext({
    required int userId,
    required ForumActionRequest request,
    required String draftContext,
  }) async {
    return claimKey(userId: userId, key: _forumKey(request, draftContext));
  }

  Future<List<ForumSubmissionTombstoneSnapshot>> listContext({
    required int userId,
    required String draftContext,
  }) async {
    final List<database.ForumActionTombstone> rows =
        await (_database.select(_database.forumActionTombstones)..where(
              (database.ForumActionTombstones table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.draftContext.equals(draftContext) &
                  table.action.isIn(
                    ForumActionKind.values
                        .map((ForumActionKind kind) => kind.name)
                        .toList(growable: false),
                  ),
            ))
            .get();
    return rows
        .map((database.ForumActionTombstone row) {
          return ForumSubmissionTombstoneSnapshot(
            attemptId: row.attemptId,
            userId: userId,
            kind: ForumActionKind.values.byName(row.action),
            target: ForumActionTarget(
              boardId: row.fid,
              threadId: row.tid,
              postId: row.pid,
              favoriteId: row.favoriteId,
            ),
            status: ForumSubmissionTombstoneStatus.values.byName(row.status),
            recordedAt: row.updatedAt,
            draftContext: row.draftContext,
          );
        })
        .toList(growable: false);
  }

  Future<void> markAttempted({
    required int userId,
    required ForumPreparedAction prepared,
    required String attemptId,
  }) async {
    return markAttemptedContext(
      userId: userId,
      request: prepared.request,
      draftContext: prepared.draftContext,
      attemptId: attemptId,
    );
  }

  Future<void> markAttemptedContext({
    required int userId,
    required ForumActionRequest request,
    required String draftContext,
    required String attemptId,
  }) async {
    return markAttemptedKey(
      userId: userId,
      key: _forumKey(request, draftContext),
      attemptId: attemptId,
    );
  }

  Future<void> resolveTrustedOutcome({
    required int userId,
    required ForumPreparedAction prepared,
    required String attemptId,
    required bool deleteDraft,
  }) {
    return resolveTrustedOutcomeContext(
      userId: userId,
      request: prepared.request,
      draftContext: prepared.draftContext,
      attemptId: attemptId,
      deleteDraft: deleteDraft,
    );
  }

  Future<void> resolveTrustedOutcomeContext({
    required int userId,
    required ForumActionRequest request,
    required String draftContext,
    required String attemptId,
    required bool deleteDraft,
  }) {
    return resolveTrustedOutcomeKey(
      userId: userId,
      key: _forumKey(request, draftContext),
      attemptId: attemptId,
      deleteDraft: deleteDraft,
    );
  }

  Future<bool> acknowledge(ForumUnresolvedSubmission submission) async {
    final int removed = await _deleteExact(
      userId: submission.userId,
      request: submission.request,
      draftContext: submission.draftContext,
      attemptId: submission.attemptId,
    );
    return removed == 1;
  }

  Future<bool> resolveSnapshot(
    ForumSubmissionTombstoneSnapshot snapshot,
  ) async {
    final int removed = await _deleteSnapshot(snapshot);
    return removed == 1;
  }

  Future<int> _deleteExact({
    required int userId,
    required ForumActionRequest request,
    required String draftContext,
    required String attemptId,
  }) {
    return _deleteKey(
      userId: userId,
      key: _forumKey(request, draftContext),
      attemptId: attemptId,
    );
  }

  Future<int> _deleteSnapshot(ForumSubmissionTombstoneSnapshot snapshot) {
    return (_database.delete(_database.forumActionTombstones)..where(
          (database.ForumActionTombstones table) =>
              table.accountKey.equals(_accountKey(snapshot.userId)) &
              table.contextKey.equals(
                _contextKeyFor(
                  _forumKeyParts(
                    snapshot.kind,
                    snapshot.target,
                    snapshot.draftContext,
                  ),
                ),
              ) &
              table.attemptId.equals(snapshot.attemptId),
        ))
        .go();
  }

  Future<int> _deleteKey({
    required int userId,
    required SubmissionTombstoneKey key,
    required String attemptId,
  }) {
    return (_database.delete(_database.forumActionTombstones)..where(
          (database.ForumActionTombstones table) =>
              table.accountKey.equals(_accountKey(userId)) &
              table.contextKey.equals(_contextKeyFor(key)) &
              table.attemptId.equals(attemptId),
        ))
        .go();
  }

  ForumUnresolvedSubmission _decode(
    SubmissionTombstoneRecord record,
    ForumActionRequest request,
    ForumReadbackDescriptor readback,
  ) {
    return ForumUnresolvedSubmission(
      attemptId: record.attemptId,
      userId: record.userId,
      request: request,
      readback: readback,
      status: record.status,
      recordedAt: record.recordedAt,
      draftContext: record.key.draftContext,
    );
  }

  SubmissionTombstoneRecord _decodeKey(
    database.ForumActionTombstone row,
    int userId,
  ) {
    return SubmissionTombstoneRecord(
      attemptId: row.attemptId,
      userId: userId,
      key: SubmissionTombstoneKey(
        action: row.action,
        boardId: row.fid,
        threadId: row.tid,
        postId: row.pid,
        favoriteId: row.favoriteId,
        draftContext: row.draftContext,
      ),
      status: ForumSubmissionTombstoneStatus.values.byName(row.status),
      recordedAt: row.updatedAt,
    );
  }

  String _accountKey(int userId) {
    if (userId <= 0) {
      throw const ForumSessionExpiredException();
    }
    return 'uid:$userId';
  }

  SubmissionTombstoneKey _forumKey(
    ForumActionRequest request,
    String draftContext,
  ) {
    return _forumKeyParts(request.kind, request.target, draftContext);
  }

  SubmissionTombstoneKey _forumKeyParts(
    ForumActionKind kind,
    ForumActionTarget target,
    String draftContext,
  ) {
    final (int? boardId, int? threadId, int? postId, int? favoriteId) =
        switch (kind) {
          ForumActionKind.reply => (null, target.threadId, null, null),
          ForumActionKind.quoteReply => (null, null, target.postId, null),
          ForumActionKind.editPost => (null, null, target.postId, null),
          _ => (
            target.boardId,
            target.threadId,
            target.postId,
            target.favoriteId,
          ),
        };
    return SubmissionTombstoneKey(
      action: kind.name,
      boardId: boardId,
      threadId: threadId,
      postId: postId,
      favoriteId: favoriteId,
      draftContext: draftContext,
    );
  }

  String _contextKeyFor(SubmissionTombstoneKey key) {
    final String canonical = <Object?>[
      key.action,
      key.boardId ?? 0,
      key.threadId ?? 0,
      key.postId ?? 0,
      key.favoriteId ?? 0,
      key.draftContext,
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  String _attemptIdFor(int userId, String action, DateTime now) {
    final String source = <Object>[
      userId,
      action,
      ++_sequence,
      now.microsecondsSinceEpoch,
      _random.nextInt(1 << 32),
      _random.nextInt(1 << 32),
    ].join(':');
    return sha256.convert(utf8.encode(source)).toString();
  }
}
