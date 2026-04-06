import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../notifiers/settlement_notifier.dart';
import '../../providers/group_providers.dart';

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
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedAmountCents != null) {
      _amountController.text =
          (widget.suggestedAmountCents! ~/ 100).toString();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountCents =
        (int.tryParse(_amountController.text) ?? 0) * 100;
    if (amountCents <= 0) return;

    setState(() => _isLoading = true);
    final group =
        await ref.read(groupDetailProvider(widget.groupId).future);

    final notifier = ref.read(settlementNotifierProvider.notifier);
    final success = await notifier.settleDebt(
      groupId: widget.groupId,
      fromMemberId: widget.fromMemberId!,
      toMemberId: widget.toMemberId!,
      amountCents: amountCents,
      currencyCode: group.currencyCode,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      context.pop();
      context.pop(); // also pop debt overview to refresh
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(title: const Text('Ghi nhận thanh toán')),
      body: groupAsync.when(
        data: (group) {
          final fromMember = group.members
              .where((m) => m.id == widget.fromMemberId)
              .firstOrNull;
          final toMember = group.members
              .where((m) => m.id == widget.toMemberId)
              .firstOrNull;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (fromMember != null && toMember != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${fromMember.name} trả ${toMember.name}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Số tiền (${group.currencyCode})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (không bắt buộc)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: _isLoading ? null : _save,
                child: const Text('Xác nhận đã trả'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }
}
