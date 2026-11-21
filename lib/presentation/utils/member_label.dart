import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';

/// How a member is shown: the viewer's own member reads "You", everyone else
/// by name.
extension MemberLabel on Member {
  /// At the start of a sentence or on its own ("You", "Bạn").
  String label(AppLocalizations l10n) => isMe ? l10n.youName : name;

  /// Inside a sentence ("Edited by you", "Tuấn đã trả bạn").
  String labelInSentence(AppLocalizations l10n) =>
      isMe ? l10n.youNameInSentence : name;
}
