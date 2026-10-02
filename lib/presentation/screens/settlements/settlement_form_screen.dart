import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/notifiers/settlement_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

class SettlementFormScreen extends ConsumerStatefulWidget {
  const SettlementFormScreen({
    super.key,
    required this.groupId,
    this.fromMemberId,
    this.toMemberId,
    this.suggestedAmountCents,
  });

  final String groupId;
  final String? fromMemberId;
  final String? toMemberId;
  final int? suggestedAmountCents;

  @override
  ConsumerState<SettlementFormScreen> createState() =>
      _SettlementFormScreenState();
}

class _SettlementFormScreenState extends ConsumerState<SettlementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSaving = false;

  /// Text initially prefilled from [SettlementFormScreen.suggestedAmountCents].
  /// When the field still holds exactly this text on save, the exact suggested
  /// cents are used, so residual sub-unit cents can always be settled.
  String? _prefilledText;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _prefillIfNeeded(Group group) {
    final suggested = widget.suggestedAmountCents;
    if (_prefilledText != null || suggested == null) return;
    _prefilledText = formatCentsForInput(suggested, group.currencyCode);
    _amountController.text = _prefilledText!;
  }

  int? _amountCents(String currencyCode) {
    final suggested = widget.suggestedAmountCents;
    if (suggested != null && _amountController.text == _prefilledText) {
      return suggested;
    }
    return parseMoneyToCents(_amountController.text, currencyCode);
  }

  Future<void> _save(Group group) async {
    if (_isSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;

    final fromId = widget.fromMemberId;
    final toId = widget.toMemberId;
    final amountCents = _amountCents(group.currencyCode);
    if (fromId == null || toId == null || amountCents == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settlementDetailsMissing)),
      );
      return;
    }

    setState(() => _isSaving = true);
    final result = await ref.read(settlementProvider.notifier).settleDebt(
          groupId: widget.groupId,
          fromMemberId: fromId,
          toMemberId: toId,
          amountCents: amountCents,
          currencyCode: group.currencyCode,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isSaving = false);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settlementRecorded)),
        );
        context.pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Watching keeps the auto-dispose notifier alive while this screen is
    // open, so the save completes on the same instance.
    final saving = ref.watch(settlementProvider).isLoading || _isSaving;
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final membersAsync = ref.watch(memberListProvider(widget.groupId));

    if (widget.fromMemberId == null || widget.toMemberId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.recordSettlement)),
        body: AppErrorWidget(
          message: l10n.settlementDetailsMissing,
          onRetry: () => context.pop(),
          retryLabel: l10n.goBack,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recordSettlement)),
      body: groupAsync.when(
        data: (group) {
          _prefillIfNeeded(group);
          final members = membersAsync.value ?? const [];
          final fromMember =
              members.where((m) => m.id == widget.fromMemberId).firstOrNull;
          final toMember =
              members.where((m) => m.id == widget.toMemberId).firstOrNull;

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (fromMember != null && toMember != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.owes(fromMember.name, toMember.name),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: currencyHasDecimals(group.currencyCode),
                  ),
                  decoration: InputDecoration(
                    labelText: '${l10n.amount} (${group.currencyCode})',
                  ),
                  validator: (_) {
                    final cents = _amountCents(group.currencyCode);
                    if (cents == null || cents <= 0) return l10n.invalidAmount;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: l10n.note,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving ? null : () => _save(group),
                  child: Text(l10n.confirmPaid),
                ),
              ],
            ),
          );
        },
        loading: () => const AppLoadingWidget(),
        error: (e, _) => AppErrorWidget(
          error: e,
          onRetry: () => ref.invalidate(groupDetailProvider(widget.groupId)),
        ),
      ),
    );
  }
}
