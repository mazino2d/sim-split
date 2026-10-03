import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

/// One recorded payment in the settlement history: "A paid B", its date and
/// optional note, and the amount.
class SettlementListTile extends StatelessWidget {
  const SettlementListTile({
    super.key,
    required this.settlement,
    required this.members,
  });

  final Settlement settlement;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String nameOf(String memberId) {
      final member = members.where((m) => m.id == memberId).firstOrNull;
      if (member == null) return '?';
      return member.isMe ? '${member.name} ${l10n.meLabel}' : member.name;
    }

    final locale = Localizations.localeOf(context).toLanguageTag();
    final date =
        DateFormat('d MMM yyyy', locale).format(settlement.settledAt.toLocal());
    final note = settlement.note;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, size: 20, color: cs.onSurface),
      ),
      title: Text(
        l10n.paidTo(
          nameOf(settlement.fromMemberId),
          nameOf(settlement.toMemberId),
        ),
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        note == null || note.isEmpty ? date : '$date · $note',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: MoneyText(
        settlement.amountCents,
        settlement.currencyCode,
        style: theme.textTheme.titleSmall,
      ),
    );
  }
}
