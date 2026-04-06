import 'package:drift/drift.dart';
import '../../domain/entities/member.dart';
import '../database/app_database.dart' as db;

class MemberMapper {
  const MemberMapper();

  Member toEntity(db.Member row) => Member(
        id: row.id,
        groupId: row.groupId,
        name: row.name,
        avatarColorValue: row.avatarColorValue,
        isMe: row.isMe,
        createdAt: row.createdAt,
      );

  db.MembersCompanion toCompanion(Member entity) => db.MembersCompanion(
        id: Value(entity.id),
        groupId: Value(entity.groupId),
        name: Value(entity.name),
        avatarColorValue: Value(entity.avatarColorValue),
        isMe: Value(entity.isMe),
        createdAt: Value(entity.createdAt),
      );
}
