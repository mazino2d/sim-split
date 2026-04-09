import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';
import 'package:simsplit/presentation/notifiers/expense_notifier.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.groupId,
    this.editExpenseId,
  });

  final String groupId;
  final String? editExpenseId;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;
  String? _paidByMemberId;
  List<Member> _members = [];
  DateTime _expenseDate = DateTime.now();
  bool _isDirty = false;

  // Per-member split controllers and focus nodes
  final Map<String, TextEditingController> _splitControllers = {};
  final Map<String, FocusNode> _splitFocusNodes = {};
  final Map<String, String> _prevSplitTexts = {};

  bool _membersInitialized = false;
  bool _loadedExistingExpense = false;
  bool _isRedistributing = false;

  bool get isEdit => widget.editExpenseId != null;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() => _isDirty = true));
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    setState(() => _isDirty = true);
    if (_splitType == SplitType.exact && _membersInitialized) {
      _applyDefaultSplits();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    for (final c in _splitControllers.values) {
      c.dispose();
    }
    for (final f in _splitFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Initialization ────────────────────────────────────────────────────────

  void _initMemberControllers(List<Member> members) {
    if (_membersInitialized) return;
    _membersInitialized = true;
    _members = members;
    // Default payer: prefer "me" member
    _paidByMemberId ??= members.where((m) => m.isMe).firstOrNull?.id
        ?? (members.isNotEmpty ? members.first.id : null);

    for (final m in members) {
      _splitControllers[m.id] = TextEditingController(text: '0');
      _splitFocusNodes[m.id] = FocusNode()
        ..addListener(() => _onFocusChanged(m.id));
    }
  }

  void _onFocusChanged(String memberId) {
    final focusNode = _splitFocusNodes[memberId]!;
    if (focusNode.hasFocus) {
      _prevSplitTexts[memberId] = _splitControllers[memberId]?.text ?? '0';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctrl = _splitControllers[memberId];
        if (ctrl == null) return;
        ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      });
    } else {
      final ctrl = _splitControllers[memberId];
      if (ctrl != null && ctrl.text.trim().isEmpty) {
        setState(() {
          ctrl.text = _prevSplitTexts[memberId] ?? _defaultTextForType();
        });
      }
      if (_splitType == SplitType.percentage || _splitType == SplitType.exact) {
        _redistributeAfterBlur(memberId);
      }
    }
  }

  String _defaultTextForType() => switch (_splitType) {
        SplitType.percentage => '0.00',
        SplitType.shares => '1',
        _ => '0',
      };

  void _loadExistingExpense(Expense expense) {
    if (_loadedExistingExpense || _members.isEmpty) return;
    _loadedExistingExpense = true;

    _titleController.text = expense.title;
    _amountController.text = (expense.amountCents ~/ 100).toString();
    _paidByMemberId = expense.paidByMemberId;
    _splitType = expense.splitType;
    _expenseDate = expense.expenseDate.toLocal();

    for (final split in expense.splits) {
      final ctrl = _splitControllers[split.memberId];
      if (ctrl == null) continue;
      ctrl.text = switch (expense.splitType) {
        SplitType.percentage =>
          (split.value / 100).toStringAsFixed(2),
        SplitType.exact =>
          (split.amountCents ~/ 100).toString(),
        SplitType.shares => split.value.toString(),
        SplitType.equal => '0',
      };
    }
    // Reset dirty after loading existing data
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _isDirty = false));
  }

  // ── Default & Redistribute ────────────────────────────────────────────────

  void _applyDefaultSplits() {
    if (_members.isEmpty) return;
    final N = _members.length;
    final displayAmt = _parseDisplayAmount();

    setState(() {
      switch (_splitType) {
        case SplitType.percentage:
          final base = 10000 ~/ N;
          for (var i = 0; i < N; i++) {
            final val = i == N - 1 ? 10000 - (N - 1) * base : base;
            _splitControllers[_members[i].id]?.text =
                (val / 100).toStringAsFixed(2);
          }
        case SplitType.exact:
          final base = displayAmt ~/ N;
          for (var i = 0; i < N; i++) {
            final val = i == N - 1 ? displayAmt - (N - 1) * base : base;
            _splitControllers[_members[i].id]?.text = val.toString();
          }
        case SplitType.shares:
          for (final m in _members) {
            _splitControllers[m.id]?.text = '1';
          }
        case SplitType.equal:
          break;
      }
    });
  }

  void _redistributeAfterBlur(String changedMemberId) {
    if (_isRedistributing || _members.length <= 1) return;
    _isRedistributing = true;

    try {
      final others = _members.where((m) => m.id != changedMemberId).toList();
      final M = others.length;

      if (_splitType == SplitType.percentage) {
        final changedText = _splitControllers[changedMemberId]?.text ?? '0.00';
        final changedVal = ((double.tryParse(changedText) ?? 0) * 100).round();
        final remaining = 10000 - changedVal;
        final base = remaining ~/ M;
        setState(() {
          for (var i = 0; i < M; i++) {
            if (_splitFocusNodes[others[i].id]?.hasFocus == true) continue;
            final val = i == M - 1 ? remaining - (M - 1) * base : base;
            _splitControllers[others[i].id]?.text =
                (val / 100).toStringAsFixed(2);
          }
        });
      } else if (_splitType == SplitType.exact) {
        final changedText = _splitControllers[changedMemberId]?.text ?? '0';
        final changedVal =
            int.tryParse(changedText.replaceAll(',', '').replaceAll('.', '')) ??
                0;
        final displayAmt = _parseDisplayAmount();
        final remaining = displayAmt - changedVal;
        final base = remaining ~/ M;
        setState(() {
          for (var i = 0; i < M; i++) {
            if (_splitFocusNodes[others[i].id]?.hasFocus == true) continue;
            final val = i == M - 1 ? remaining - (M - 1) * base : base;
            _splitControllers[others[i].id]?.text = val.toString();
          }
        });
      }
    } finally {
      _isRedistributing = false;
    }
  }

  int _parseDisplayAmount() {
    final text = _amountController.text.replaceAll(',', '').replaceAll('.', '');
    return int.tryParse(text) ?? 0;
  }

  // ── Build RawSplitInputs ──────────────────────────────────────────────────

  List<RawSplitInput> _buildSplitInputs() {
    return _members.map((m) {
      final text = _splitControllers[m.id]?.text ?? '0';
      final int val;
      switch (_splitType) {
        case SplitType.percentage:
          val = ((double.tryParse(text) ?? 0) * 100).round();
        case SplitType.exact:
          val = (int.tryParse(text.replaceAll(',', '').replaceAll('.', '')) ??
                  0) *
              100;
        case SplitType.shares:
          val = int.tryParse(text) ?? 0;
        case SplitType.equal:
          val = 0;
      }
      return RawSplitInput(memberId: m.id, value: val);
    }).toList();
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.deleteExpenseConfirmTitle),
        content: Text(l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await ref
        .read(expenseNotifierProvider.notifier)
        .deleteExpense(widget.editExpenseId!);
    if (!success) return;
    if (!mounted) return;
    _isDirty = false;
    context.go('/groups/${widget.groupId}');
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paidByMemberId == null) return;

    final l10n = AppLocalizations.of(context)!;
    final amountCents = _parseDisplayAmount() * 100;
    final notifier = ref.read(expenseNotifierProvider.notifier);
    final group = await ref.read(groupDetailProvider(widget.groupId).future);

    bool success;
    if (isEdit) {
      success = await notifier.editExpense(
        id: widget.editExpenseId!,
        title: _titleController.text.trim(),
        amountCents: amountCents,
        currencyCode: group.currencyCode,
        paidByMemberId: _paidByMemberId!,
        splitType: _splitType,
        splitInputs: _buildSplitInputs(),
        expenseDate: _expenseDate,
      );
    } else {
      success = await notifier.addExpense(
        groupId: widget.groupId,
        title: _titleController.text.trim(),
        amountCents: amountCents,
        currencyCode: group.currencyCode,
        paidByMemberId: _paidByMemberId!,
        splitType: _splitType,
        splitInputs: _buildSplitInputs(),
        expenseDate: _expenseDate,
      );
    }

    if (!mounted) return;
    if (success) {
      _isDirty = false;
      context.pop();
    } else {
      final error = ref.read(expenseNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error?.toString() ?? l10n.errorUnexpected)),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unsavedChanges),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.keepEditing),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discardChanges),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final membersAsync = ref.watch(memberListProvider(widget.groupId));
    final expensesAsync =
        isEdit ? ref.watch(expenseListProvider(widget.groupId)) : null;

    if (groupAsync.isLoading || membersAsync.isLoading) {
      return const Scaffold(body: AppLoadingWidget());
    }
    if (groupAsync.hasError) {
      return Scaffold(body: Center(child: Text(groupAsync.error.toString())));
    }

    final group = groupAsync.requireValue;
    final members = membersAsync.valueOrNull ?? [];
    _initMemberControllers(members);

    if (isEdit && expensesAsync != null) {
      final expenses = expensesAsync.valueOrNull ?? [];
      final existing =
          expenses.where((e) => e.id == widget.editExpenseId).firstOrNull;
      if (existing != null && !_loadedExistingExpense) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _loadExistingExpense(existing)));
      }
    }

    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateLabel = DateFormat('d MMM yyyy', locale).format(_expenseDate);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        if (canLeave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? l10n.editExpense : l10n.addExpense),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: l10n.save,
              onPressed: _save,
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Title ────────────────────────────────────────────────
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10n.expenseTitle,
                  hintText: l10n.expenseTitleHint,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.expenseTitleRequired
                    : null,
              ),
              const SizedBox(height: 12),

              // ── Amount ───────────────────────────────────────────────
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${l10n.amount} (${group.currencyCode})',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(
                      v?.replaceAll(',', '').replaceAll('.', '') ?? '');
                  if (n == null || n <= 0) return l10n.invalidAmount;
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Date picker ──────────────────────────────────────────
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(dateLabel),
                  subtitle: Text(l10n.date),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _expenseDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _expenseDate = picked;
                        _isDirty = true;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),

              // ── Paid by ──────────────────────────────────────────────
              DropdownButtonFormField<String>(
                initialValue: _paidByMemberId,
                decoration: InputDecoration(
                  labelText: l10n.paidBy,
                  border: const OutlineInputBorder(),
                ),
                items: members
                    .map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.isMe
                              ? '${m.name} ${l10n.meLabel}'
                              : m.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _paidByMemberId = v;
                  _isDirty = true;
                }),
              ),
              const SizedBox(height: 16),

              // ── Split type (2×2 grid) ─────────────────────────────────
              Text(l10n.splitType,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _buildSplitTypeGrid(l10n),
              const SizedBox(height: 16),

              // ── Per-member inputs ─────────────────────────────────────
              if (_splitType != SplitType.equal) ...[
                _buildSplitHeader(l10n, group.currencyCode),
                const SizedBox(height: 8),
                for (final member in members)
                  _buildMemberSplitRow(member, group.currencyCode),
                const SizedBox(height: 8),
                _buildSplitSumIndicator(group.currencyCode),
              ],

              const SizedBox(height: 24),

              // ── Delete button (bottom, edit mode) ─────────────────────
              if (isEdit) ...[
                const Divider(),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.deleteExpense),
                    onPressed: _confirmDelete,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplitTypeGrid(AppLocalizations l10n) {
    final types = [
      (SplitType.equal, l10n.splitEqual, Icons.people_outline),
      (SplitType.percentage, l10n.splitPercentage, Icons.percent),
      (SplitType.exact, l10n.splitExact, Icons.attach_money),
      (SplitType.shares, l10n.splitShares, Icons.bar_chart),
    ];

    return Column(
      children: [
        Row(
          children: types.take(2).map((t) => _splitTypeChip(t)).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: types.skip(2).map((t) => _splitTypeChip(t)).toList(),
        ),
      ],
    );
  }

  Widget _splitTypeChip(
      (SplitType, String, IconData) typeData) {
    final (type, label, icon) = typeData;
    final isSelected = _splitType == type;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () {
            setState(() {
              _splitType = type;
              _isDirty = true;
            });
            _applyDefaultSplits();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitHeader(AppLocalizations l10n, String currencyCode) {
    return Text(
      switch (_splitType) {
        SplitType.percentage => l10n.percentageMustSum100,
        SplitType.exact => '${l10n.amount} ($currencyCode)',
        SplitType.shares => l10n.splitShares,
        SplitType.equal => '',
      },
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildMemberSplitRow(Member member, String currencyCode) {
    final ctrl = _splitControllers[member.id];
    final focusNode = _splitFocusNodes[member.id];
    if (ctrl == null || focusNode == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Color(member.avatarColorValue),
            child: member.emoji != null
                ? Text(member.emoji!,
                    style: const TextStyle(fontSize: 14))
                : Text(
                    member.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(member.name, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: switch (_splitType) {
                  SplitType.percentage => '0.00',
                  SplitType.exact => '0',
                  SplitType.shares => '1',
                  SplitType.equal => '',
                },
                suffixText: switch (_splitType) {
                  SplitType.percentage => '%',
                  SplitType.exact => currencyCode,
                  SplitType.shares => '×',
                  SplitType.equal => '',
                },
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitSumIndicator(String currencyCode) {
    final l10n = AppLocalizations.of(context)!;
    if (_splitType == SplitType.percentage) {
      final total = _members.fold<double>(0, (sum, m) {
        final t = _splitControllers[m.id]?.text ?? '0';
        return sum + (double.tryParse(t) ?? 0);
      });
      final isValid = (total * 100).round() == 10000;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(isValid ? Icons.check_circle : Icons.info_outline,
              size: 16, color: isValid ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(
            l10n.splitSumPercentage(total.toStringAsFixed(2)),
            style: TextStyle(
              color: isValid ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    if (_splitType == SplitType.exact) {
      final totalEntered = _members.fold<int>(0, (sum, m) {
        final t = _splitControllers[m.id]?.text ?? '0';
        return sum +
            (int.tryParse(t.replaceAll(',', '').replaceAll('.', '')) ?? 0);
      });
      final target = _parseDisplayAmount();
      final isValid = totalEntered == target;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(isValid ? Icons.check_circle : Icons.info_outline,
              size: 16, color: isValid ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(
            l10n.splitSumExact(
              formatMoney(totalEntered * 100, currencyCode),
              formatMoney(target * 100, currencyCode),
            ),
            style: TextStyle(
              color: isValid ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
