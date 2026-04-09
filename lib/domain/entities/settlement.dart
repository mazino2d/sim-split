import 'package:freezed_annotation/freezed_annotation.dart';

part 'settlement.freezed.dart';

@freezed
sealed class Settlement with _$Settlement {
  const factory Settlement({
    required String id,
    required String groupId,
    required String fromMemberId,
    required String toMemberId,
    required int amountCents,
    required String currencyCode,
    String? note,
    required DateTime settledAt,
    required DateTime createdAt,
  }) = _Settlement;
}
