import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

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
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(Icons.payments_outlined,
            color: colorScheme.onSecondaryContainer),
      ),
      title: Text(l10n.paidTo(
        nameOf(settlement.fromMemberId),
        nameOf(settlement.toMemberId),
      )),
      subtitle: Text(
        note == null || note.isEmpty ? date : '$date · $note',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: Text(
        formatMoney(settlement.amountCents, settlement.currencyCode),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
