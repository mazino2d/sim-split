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
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/member_initial.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
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
  bool _isSaving = false;

  /// Currency of the group; set on every build from the loaded group.
  String _currencyCode = 'VND';

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
    _paidByMemberId ??= members.where((m) => m.isMe).firstOrNull?.id ??
        (members.isNotEmpty ? members.first.id : null);

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
    _amountController.text =
        formatCentsForInput(expense.amountCents, _currencyCode);
    _paidByMemberId = expense.paidByMemberId;
    _splitType = expense.splitType;
    _expenseDate = expense.expenseDate.toLocal();

    for (final split in expense.splits) {
      final ctrl = _splitControllers[split.memberId];
      if (ctrl == null) continue;
      ctrl.text = switch (expense.splitType) {
        SplitType.percentage => (split.value / 100).toStringAsFixed(2),
        SplitType.exact =>
          formatCentsForInput(split.amountCents, _currencyCode),
        SplitType.shares => split.value.toString(),
        SplitType.equal => '0',
      };
    }
    // Reset dirty after loading existing data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isDirty = false);
    });
  }

  // ── Parsing helpers ───────────────────────────────────────────────────────

  /// Total amount in cents, or null when the input is invalid.
  int? _parseAmountCents() =>
      parseMoneyToCents(_amountController.text, _currencyCode);

  /// Percentage input scaled ×100 (33.33% → 3333), or null when invalid.
  int? _parsePercentScaled(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final v = double.tryParse(normalized);
    if (v == null || v.isNaN || v < 0) return null;
    return (v * 100).round();
  }

  int? _parseShares(String text) => int.tryParse(text.trim());

  /// Splits [total] cents across [count] members in multiples of the
  /// currency's input step; the last member absorbs the remainder.
  /// Never produces negative values.
  List<int> _distributeCents(int total, int count) {
    if (count <= 0) return const [];
    final safeTotal = total < 0 ? 0 : total;
    final step = inputStepCents(_currencyCode);
    final units = safeTotal ~/ step;
    final baseUnits = units ~/ count;
    return [
      for (var i = 0; i < count; i++)
        i == count - 1
            ? safeTotal - (count - 1) * baseUnits * step
            : baseUnits * step,
    ];
  }

  // ── Default & Redistribute ────────────────────────────────────────────────

  void _applyDefaultSplits() {
    if (_members.isEmpty) return;
    final n = _members.length;

    setState(() {
      switch (_splitType) {
        case SplitType.percentage:
          final base = 10000 ~/ n;
          for (var i = 0; i < n; i++) {
            final val = i == n - 1 ? 10000 - (n - 1) * base : base;
            _splitControllers[_members[i].id]?.text =
                (val / 100).toStringAsFixed(2);
          }
        case SplitType.exact:
          final values = _distributeCents(_parseAmountCents() ?? 0, n);
          for (var i = 0; i < n; i++) {
            _splitControllers[_members[i].id]?.text =
                formatCentsForInput(values[i], _currencyCode);
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
      final others = _members
          .where((m) => m.id != changedMemberId)
          .where((m) => _splitFocusNodes[m.id]?.hasFocus != true)
          .toList();
      if (others.isEmpty) return;
      final changedText = _splitControllers[changedMemberId]?.text ?? '';

      if (_splitType == SplitType.percentage) {
        final changedVal = _parsePercentScaled(changedText);
        if (changedVal == null) return; // invalid input: leave others as-is
        final remaining = (10000 - changedVal).clamp(0, 10000);
        final m = others.length;
        final base = remaining ~/ m;
        setState(() {
          for (var i = 0; i < m; i++) {
            final val = i == m - 1 ? remaining - (m - 1) * base : base;
            _splitControllers[others[i].id]?.text =
                (val / 100).toStringAsFixed(2);
          }
        });
      } else if (_splitType == SplitType.exact) {
        final changedVal = parseMoneyToCents(changedText, _currencyCode);
        final total = _parseAmountCents();
        if (changedVal == null || total == null) return;
        final remaining = total - changedVal;
        final values = _distributeCents(remaining, others.length);
        setState(() {
          for (var i = 0; i < others.length; i++) {
            _splitControllers[others[i].id]?.text =
                formatCentsForInput(values[i], _currencyCode);
          }
        });
      }
    } finally {
      _isRedistributing = false;
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validateSplitField(String? value, AppLocalizations l10n) {
    final text = value ?? '';
    switch (_splitType) {
      case SplitType.percentage:
        final v = _parsePercentScaled(text);
        if (v == null || v > 10000) return l10n.invalidPercentage;
      case SplitType.exact:
        final v = parseMoneyToCents(text, _currencyCode);
        if (v == null) return l10n.invalidAmount;
        final total = _parseAmountCents();
        if (total != null && v > total) return l10n.exceedsTotal;
      case SplitType.shares:
        final v = _parseShares(text);
        if (v == null || v < 1) return l10n.invalidShares;
      case SplitType.equal:
        break;
    }
    return null;
  }

  // ── Build RawSplitInputs ──────────────────────────────────────────────────

  List<RawSplitInput> _buildSplitInputs() {
    return _members.map((m) {
      final text = _splitControllers[m.id]?.text ?? '0';
      final int val = switch (_splitType) {
        SplitType.percentage => _parsePercentScaled(text) ?? 0,
        SplitType.exact => parseMoneyToCents(text, _currencyCode) ?? 0,
        SplitType.shares => _parseShares(text) ?? 0,
        SplitType.equal => 0,
      };
      return RawSplitInput(memberId: m.id, value: val);
    }).toList();
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    if (_isSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dCtx).colorScheme.error,
              foregroundColor: Theme.of(dCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSaving = true);
    final result = await ref
        .read(expenseProvider.notifier)
        .deleteExpense(widget.editExpenseId!);
    if (!mounted) return;
    setState(() => _isSaving = false);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) {
        _isDirty = false;
        context.go('/groups/${widget.groupId}');
      },
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_isSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;
    final amountCents = _parseAmountCents();
    final paidBy = _paidByMemberId;
    if (paidBy == null || amountCents == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorMemberNotFound)),
      );
      return;
    }

    setState(() => _isSaving = true);
    final notifier = ref.read(expenseProvider.notifier);
    final result = isEdit
        ? await notifier.editExpense(
            id: widget.editExpenseId!,
            title: _titleController.text.trim(),
            amountCents: amountCents,
            currencyCode: _currencyCode,
            paidByMemberId: paidBy,
            splitType: _splitType,
            splitInputs: _buildSplitInputs(),
            expenseDate: _expenseDate,
          )
        : await notifier.addExpense(
            groupId: widget.groupId,
            title: _titleController.text.trim(),
            amountCents: amountCents,
            currencyCode: _currencyCode,
            paidByMemberId: paidBy,
            splitType: _splitType,
            splitInputs: _buildSplitInputs(),
            expenseDate: _expenseDate,
          );

    if (!mounted) return;
    setState(() => _isSaving = false);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) {
        _isDirty = false;
        context.pop();
      },
    );
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discardChanges),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Scaffold _messageScaffold(String title, Widget body) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = isEdit ? l10n.editExpense : l10n.addExpense;
    // Watching keeps the auto-dispose notifier alive while the screen is
    // open and lets us disable Save while a mutation is running.
    final saving = ref.watch(expenseProvider).isLoading || _isSaving;
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final membersAsync = ref.watch(memberListProvider(widget.groupId));
    final expensesAsync =
        isEdit ? ref.watch(expenseListProvider(widget.groupId)) : null;

    if (groupAsync.hasError || membersAsync.hasError) {
      final error = groupAsync.error ?? membersAsync.error;
      return _messageScaffold(
        title,
        AppErrorWidget(
          error: error,
          onRetry: () {
            ref.invalidate(groupDetailProvider(widget.groupId));
            ref.invalidate(memberListProvider(widget.groupId));
          },
        ),
      );
    }
    if (!groupAsync.hasValue || !membersAsync.hasValue) {
      return const Scaffold(body: AppLoadingWidget());
    }

    final group = groupAsync.requireValue;
    _currencyCode = group.currencyCode;
    final members = membersAsync.requireValue;
    _initMemberControllers(members);

    if (isEdit && expensesAsync != null && !_loadedExistingExpense) {
      if (expensesAsync.hasError) {
        return _messageScaffold(
          title,
          AppErrorWidget(
            error: expensesAsync.error,
            onRetry: () => ref.invalidate(expenseListProvider(widget.groupId)),
          ),
        );
      }
      if (!expensesAsync.hasValue) {
        return const Scaffold(body: AppLoadingWidget());
      }
      final existing = expensesAsync.requireValue
          .where((e) => e.id == widget.editExpenseId)
          .firstOrNull;
      if (existing == null) {
        return _messageScaffold(
          title,
          AppErrorWidget(
            message: l10n.expenseNotFound,
            onRetry: () => context.pop(),
            retryLabel: l10n.goBack,
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadExistingExpense(existing));
      });
    }

    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateLabel = DateFormat('d MMM yyyy', locale).format(_expenseDate);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        if (canLeave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: l10n.save,
              onPressed: saving ? null : _save,
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
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.expenseTitleRequired
                    : null,
              ),
              const SizedBox(height: 12),

              // ── Amount ───────────────────────────────────────────────
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: currencyHasDecimals(group.currencyCode),
                ),
                decoration: InputDecoration(
                  labelText: '${l10n.amount} (${group.currencyCode})',
                ),
                validator: (v) {
                  final n = parseMoneyToCents(v ?? '', group.currencyCode);
                  if (n == null || n <= 0) return l10n.invalidAmount;
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Paid by ──────────────────────────────────────────────
              DropdownButtonFormField<String>(
                key: ValueKey('paidBy-$_paidByMemberId'),
                initialValue: _paidByMemberId,
                decoration: InputDecoration(
                  labelText: l10n.paidBy,
                ),
                items: members
                    .map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(
                              m.isMe ? '${m.name} ${l10n.meLabel}' : m.name),
                        ))
                    .toList(),
                validator: (v) => v == null ? l10n.errorMemberNotFound : null,
                onChanged: (v) => setState(() {
                  _paidByMemberId = v;
                  _isDirty = true;
                }),
              ),
              const SizedBox(height: 12),

              // ── Date picker ──────────────────────────────────────────
              Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 18, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(child: Text(dateLabel)),
                        Icon(Icons.expand_more,
                            size: 18, color: colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
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
                  _buildMemberSplitRow(member, group.currencyCode, l10n),
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
                    style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.deleteExpense),
                    onPressed: saving ? null : _confirmDelete,
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

  Widget _splitTypeChip((SplitType, String, IconData) typeData) {
    final (type, label, icon) = typeData;
    final isSelected = _splitType == type;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          button: true,
          selected: isSelected,
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
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
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

  Widget _buildMemberSplitRow(
    Member member,
    String currencyCode,
    AppLocalizations l10n,
  ) {
    final ctrl = _splitControllers[member.id];
    final focusNode = _splitFocusNodes[member.id];
    if (ctrl == null || focusNode == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Color(member.avatarColorValue),
              child: member.emoji != null
                  ? Text(member.emoji!, style: const TextStyle(fontSize: 14))
                  : Text(
                      nameInitial(member.name),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(member.name, overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _splitType == SplitType.percentage ||
                    (_splitType == SplitType.exact &&
                        currencyHasDecimals(currencyCode)),
              ),
              onChanged: (_) => setState(() => _isDirty = true),
              validator: (v) => _validateSplitField(v, l10n),
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
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSumRow(bool isValid, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isValid ? colorScheme.primary : colorScheme.error;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(isValid ? Icons.check_circle : Icons.info_outline,
            size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSplitSumIndicator(String currencyCode) {
    final l10n = AppLocalizations.of(context)!;
    if (_splitType == SplitType.percentage) {
      final totalScaled = _members.fold<int>(0, (sum, m) {
        final t = _splitControllers[m.id]?.text ?? '0';
        return sum + (_parsePercentScaled(t) ?? 0);
      });
      return _buildSumRow(
        totalScaled == 10000,
        l10n.splitSumPercentage((totalScaled / 100).toStringAsFixed(2)),
      );
    }
    if (_splitType == SplitType.exact) {
      final totalEntered = _members.fold<int>(0, (sum, m) {
        final t = _splitControllers[m.id]?.text ?? '0';
        return sum + (parseMoneyToCents(t, currencyCode) ?? 0);
      });
      final target = _parseAmountCents() ?? 0;
      return _buildSumRow(
        totalEntered == target,
        l10n.splitSumExact(
          formatMoney(totalEntered, currencyCode),
          formatMoney(target, currencyCode),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
