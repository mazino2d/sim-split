import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/expense.dart';
import '../../../domain/entities/expense_split.dart';
import '../../../domain/entities/member.dart';
import '../../../domain/use_cases/expenses/calculate_splits.dart';
import '../../notifiers/expense_notifier.dart';
import '../../providers/group_providers.dart';
import '../../widgets/common/loading_widget.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.groupId,
    this.editExpenseId,
  });

  final String groupId;
  final String? editExpenseId;

  @override
  ConsumerState<ExpenseFormScreen> createState() =>
      _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;
  String? _paidByMemberId;
  List<Member> _members = [];

  // Per-member split input values (scaled for percentage / raw for others)
  final Map<String, int> _splitValues = {};
  final Map<String, TextEditingController> _splitControllers = {};

  bool get isEdit => widget.editExpenseId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    for (final c in _splitControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initSplitControllers(List<Member> members) {
    if (_members.isNotEmpty) return; // already initialized
    _members = members;
    _paidByMemberId ??= members.isNotEmpty ? members.first.id : null;

    for (final m in members) {
      _splitValues[m.id] = 0;
      _splitControllers[m.id] = TextEditingController(text: '0');
    }
  }

  List<RawSplitInput> _buildSplitInputs() {
    return _members.map((m) {
      final val = int.tryParse(_splitControllers[m.id]?.text ?? '0') ?? 0;
      return RawSplitInput(memberId: m.id, value: val);
    }).toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paidByMemberId == null) return;

    final amountStr = _amountController.text.replaceAll(',', '').replaceAll('.', '');
    final amountCents = (int.tryParse(amountStr) ?? 0) * 100;

    final notifier = ref.read(expenseNotifierProvider.notifier);
    final group =
        await ref.read(groupDetailProvider(widget.groupId).future);

    bool success;
    if (isEdit) {
      success = await notifier.editExpense(
        id: widget.editExpenseId!,
        title: _titleController.text,
        amountCents: amountCents,
        currencyCode: group.currencyCode,
        paidByMemberId: _paidByMemberId!,
        splitType: _splitType,
        splitInputs: _buildSplitInputs(),
      );
    } else {
      success = await notifier.addExpense(
        groupId: widget.groupId,
        title: _titleController.text,
        amountCents: amountCents,
        currencyCode: group.currencyCode,
        paidByMemberId: _paidByMemberId!,
        splitType: _splitType,
        splitInputs: _buildSplitInputs(),
      );
    }

    if (!mounted) return;
    if (success) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final membersAsync = ref.watch(memberListProvider(widget.groupId));

    if (groupAsync.isLoading || membersAsync.isLoading) {
      return const Scaffold(body: AppLoadingWidget());
    }
    if (groupAsync.hasError) {
      return Scaffold(body: Center(child: Text(groupAsync.error.toString())));
    }

    final group = groupAsync.requireValue;
    final members = membersAsync.valueOrNull ?? [];
    _initSplitControllers(members);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa chi tiêu' : 'Thêm chi tiêu'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                hintText: 'vd. Ăn tối',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Vui lòng nhập mô tả'
                  : null,
            ),
            const SizedBox(height: 12),

            // Amount
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Số tiền (${group.currencyCode})',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(
                    v?.replaceAll(',', '').replaceAll('.', '') ?? '');
                if (n == null || n <= 0) return 'Nhập số tiền hợp lệ';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Paid by
            DropdownButtonFormField<String>(
              value: _paidByMemberId,
              decoration: const InputDecoration(
                labelText: 'Người trả',
                border: OutlineInputBorder(),
              ),
              items: members
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _paidByMemberId = v),
            ),
            const SizedBox(height: 16),

            // Split type selector
            const Text('Kiểu chia',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<SplitType>(
              segments: const [
                ButtonSegment(
                    value: SplitType.equal, label: Text('Đều')),
                ButtonSegment(
                    value: SplitType.percentage, label: Text('%')),
                ButtonSegment(
                    value: SplitType.exact, label: Text('Số tiền')),
                ButtonSegment(
                    value: SplitType.shares, label: Text('Tỉ lệ')),
              ],
              selected: {_splitType},
              onSelectionChanged: (s) =>
                  setState(() => _splitType = s.first),
            ),
            const SizedBox(height: 16),

            // Per-member split inputs (shown for non-equal)
            if (_splitType != SplitType.equal) ...[
              const Text('Chi tiết chia:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final member in members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2, child: Text(member.name)),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _splitControllers[member.id],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: _splitType == SplitType.percentage
                                ? '0–100 (%×100)'
                                : _splitType == SplitType.exact
                                    ? 'Cents'
                                    : 'Số phần',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _save,
              child: Text(isEdit ? 'Lưu' : 'Thêm chi tiêu'),
            ),
          ],
        ),
      ),
    );
  }
}
