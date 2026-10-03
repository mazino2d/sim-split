import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/expense_category_ui.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';

/// Add or edit an expense.
///
/// Built for the fast path: the amount is focused on open, the payer
/// defaults to whoever paid last, everyone is in the split, and Save sits
/// above the keyboard — so a typical expense is amount → Save. Description,
/// category, date, partial participation and uneven splits are all one tap
/// away but never in the way.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.groupId,
    this.editExpenseId,
    this.focusTitle = false,
  });

  final String groupId;
  final String? editExpenseId;

  /// Opens with the description focused — for filling in descriptions later
  /// on expenses that were logged with just an amount.
  final bool focusTitle;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;
  ExpenseCategory _category = ExpenseCategory.other;
  String? _paidByMemberId;
  List<Member> _members = [];
  final Set<String> _participantIds = {};
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
  bool _defaultPayerResolved = false;
  bool _loadedExistingExpense = false;
  bool _isRedistributing = false;

  bool get isEdit => widget.editExpenseId != null;

  /// Members taking part in this expense, in group order.
  List<Member> get _active =>
      _members.where((m) => _participantIds.contains(m.id)).toList();

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markDirty);
    _amountController.addListener(_onAmountChanged);
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
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
    _titleFocusNode.dispose();
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
    _participantIds.addAll(members.map((m) => m.id));
    _paidByMemberId ??= members.where((m) => m.isMe).firstOrNull?.id ??
        (members.isNotEmpty ? members.first.id : null);

    for (final m in members) {
      _splitControllers[m.id] = TextEditingController(text: '0');
      _splitFocusNodes[m.id] = FocusNode()
        ..addListener(() => _onFocusChanged(m.id));
    }
  }

  /// New expenses default the payer to whoever paid most recently: on a trip
  /// the same person often keeps paying.
  void _resolveDefaultPayer(List<Expense> expenses) {
    if (_defaultPayerResolved) return;
    _defaultPayerResolved = true;
    final lastPayer = expenses.firstOrNull?.paidByMemberId;
    if (lastPayer != null && _members.any((m) => m.id == lastPayer)) {
      _paidByMemberId = lastPayer;
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
    _category = expense.category;
    _expenseDate = expense.expenseDate.toLocal();
    _participantIds
      ..clear()
      ..addAll(expense.splits
          .map((s) => s.memberId)
          .where((id) => _splitControllers.containsKey(id)));

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
      if (!mounted) return;
      setState(() => _isDirty = false);
      if (widget.focusTitle) _focusTitle();
    });
  }

  /// Focuses the description. A title the app filled in (the category name
  /// or "Expense") is selected so typing replaces it.
  void _focusTitle() {
    final l10n = AppLocalizations.of(context)!;
    final text = _titleController.text;
    final autoTitles = {
      l10n.untitledExpense,
      for (final c in ExpenseCategory.values) c.label(l10n),
    };
    _titleFocusNode.requestFocus();
    _titleController.selection = autoTitles.contains(text)
        ? TextSelection(baseOffset: 0, extentOffset: text.length)
        : TextSelection.collapsed(offset: text.length);
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
    final active = _active;
    if (active.isEmpty) return;
    final n = active.length;

    setState(() {
      switch (_splitType) {
        case SplitType.percentage:
          final base = 10000 ~/ n;
          for (var i = 0; i < n; i++) {
            final val = i == n - 1 ? 10000 - (n - 1) * base : base;
            _splitControllers[active[i].id]?.text =
                (val / 100).toStringAsFixed(2);
          }
        case SplitType.exact:
          final values = _distributeCents(_parseAmountCents() ?? 0, n);
          for (var i = 0; i < n; i++) {
            _splitControllers[active[i].id]?.text =
                formatCentsForInput(values[i], _currencyCode);
          }
        case SplitType.shares:
          for (final m in active) {
            _splitControllers[m.id]?.text = '1';
          }
        case SplitType.equal:
          break;
      }
    });
  }

  void _redistributeAfterBlur(String changedMemberId) {
    final active = _active;
    if (_isRedistributing || active.length <= 1) return;
    _isRedistributing = true;

    try {
      final others = active
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

  void _setSplitType(SplitType type) {
    setState(() {
      _splitType = type;
      _isDirty = true;
    });
    _applyDefaultSplits();
  }

  void _toggleParticipant(String memberId) {
    setState(() {
      if (!_participantIds.remove(memberId)) _participantIds.add(memberId);
      _isDirty = true;
    });
    if (_splitType != SplitType.equal) _applyDefaultSplits();
  }

  void _setAllParticipants(bool all) {
    setState(() {
      _participantIds.clear();
      if (all) _participantIds.addAll(_members.map((m) => m.id));
      _isDirty = true;
    });
    if (_splitType != SplitType.equal) _applyDefaultSplits();
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
    return _active.map((m) {
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
              minimumSize: const Size(64, 44),
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
    if (_participantIds.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorNoParticipants)),
      );
      return;
    }
    final amountCents = _parseAmountCents();
    final paidBy = _paidByMemberId;
    if (paidBy == null || amountCents == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorMemberNotFound)),
      );
      return;
    }

    // The description is optional: fall back to the category name.
    final typed = _titleController.text.trim();
    final title = typed.isNotEmpty
        ? typed
        : _category == ExpenseCategory.other
            ? l10n.untitledExpense
            : _category.label(l10n);

    setState(() => _isSaving = true);
    final notifier = ref.read(expenseProvider.notifier);
    final result = isEdit
        ? await notifier.editExpense(
            id: widget.editExpenseId!,
            title: title,
            amountCents: amountCents,
            currencyCode: _currencyCode,
            paidByMemberId: paidBy,
            splitType: _splitType,
            splitInputs: _buildSplitInputs(),
            expenseDate: _expenseDate,
            category: _category,
          )
        : await notifier.addExpense(
            groupId: widget.groupId,
            title: title,
            amountCents: amountCents,
            currencyCode: _currencyCode,
            paidByMemberId: paidBy,
            splitType: _splitType,
            splitInputs: _buildSplitInputs(),
            expenseDate: _expenseDate,
            category: _category,
          );

    if (!mounted) return;
    setState(() => _isSaving = false);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) {
        HapticFeedback.lightImpact();
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
              minimumSize: const Size(64, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discardChanges),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _pickDate() async {
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
    final expensesAsync = ref.watch(expenseListProvider(widget.groupId));

    final loadError =
        groupAsync.error ?? membersAsync.error ?? expensesAsync.error;
    if (loadError != null) {
      return _messageScaffold(
        title,
        AppErrorWidget(
          error: loadError,
          onRetry: () {
            ref.invalidate(groupDetailProvider(widget.groupId));
            ref.invalidate(memberListProvider(widget.groupId));
            ref.invalidate(expenseListProvider(widget.groupId));
          },
        ),
      );
    }
    if (!groupAsync.hasValue ||
        !membersAsync.hasValue ||
        !expensesAsync.hasValue) {
      return const Scaffold(body: AppLoadingWidget());
    }

    final group = groupAsync.requireValue;
    _currencyCode = group.currencyCode;
    final members = membersAsync.requireValue;
    _initMemberControllers(members);

    if (isEdit) {
      if (!_loadedExistingExpense) {
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
    } else {
      _resolveDefaultPayer(expensesAsync.requireValue);
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        if (canLeave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: () => Navigator.maybePop(context)),
          title: Text(title),
          actions: [
            if (isEdit)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.deleteExpense,
                onPressed: saving ? null : _confirmDelete,
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    _buildAmountHero(l10n),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gutter),
                      child: TextFormField(
                        controller: _titleController,
                        focusNode: _titleFocusNode,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: l10n.whatFor,
                          prefixIcon:
                              Icon(_category.icon, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryChips(l10n),
                    SectionLabel(l10n.paidBy),
                    _MemberPicker(
                      members: members,
                      isSelected: (m) => m.id == _paidByMemberId,
                      meLabel: l10n.meLabel,
                      onTap: (m) => setState(() {
                        _paidByMemberId = m.id;
                        _isDirty = true;
                      }),
                    ),
                    SectionLabel(
                      l10n.splitBetween,
                      trailing: _participantIds.length == members.length
                          ? null
                          : _MiniTextButton(
                              label: l10n.everyone,
                              onPressed: () => _setAllParticipants(true),
                            ),
                    ),
                    _MemberPicker(
                      members: members,
                      isSelected: (m) => _participantIds.contains(m.id),
                      meLabel: l10n.meLabel,
                      showCheck: true,
                      onTap: (m) => _toggleParticipant(m.id),
                    ),
                    const SizedBox(height: 8),
                    _buildSplitSection(l10n, group.currencyCode),
                  ],
                ),
              ),
              _SaveBar(
                label: l10n.save,
                onPressed: saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountHero(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = DateTime.now();
    final isToday = _expenseDate.year == now.year &&
        _expenseDate.month == now.month &&
        _expenseDate.day == now.day;
    final dateLabel = isToday
        ? l10n.today
        : DateFormat('d MMM yyyy', locale).format(_expenseDate);

    final amount = _parseAmountCents();
    final n = _participantIds.length;
    final perPerson =
        _splitType == SplitType.equal && amount != null && amount > 0 && n > 1
            ? l10n.perPerson(formatMoney(amount ~/ n, _currencyCode))
            : null;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 8, AppTheme.gutter, 20),
      child: Column(
        children: [
          TextFormField(
            controller: _amountController,
            autofocus: !isEdit,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(
              decimal: currencyHasDecimals(_currencyCode),
            ),
            inputFormatters: [AmountInputFormatter(_currencyCode)],
            style: theme.textTheme.displaySmall?.copyWith(
              fontFeatures: tabularFigures,
            ),
            cursorColor: cs.onSurface,
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: '0',
              hintStyle:
                  theme.textTheme.displaySmall?.copyWith(color: cs.outline),
              errorStyle: const TextStyle(height: 1.2),
              contentPadding: EdgeInsets.zero,
            ),
            validator: (v) {
              final n = parseMoneyToCents(v ?? '', _currencyCode);
              if (n == null || n <= 0) return l10n.invalidAmount;
              return null;
            },
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                perPerson ?? _currencyCode,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              Text('·', style: TextStyle(color: cs.onSurfaceVariant)),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dateLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
        children: [
          for (final c in ExpenseCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  c.icon,
                  size: 18,
                  color: c == _category ? cs.onPrimary : cs.onSurface,
                ),
                label: Text(c.label(l10n)),
                labelStyle: TextStyle(
                  color: c == _category ? cs.onPrimary : cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                selected: c == _category,
                onSelected: (_) => setState(() {
                  _category = c;
                  _isDirty = true;
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSplitSection(AppLocalizations l10n, String currencyCode) {
    final theme = Theme.of(context);
    final uneven = _splitType != SplitType.equal;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.splitUnevenly,
                      style: theme.textTheme.bodyLarge),
                ),
                Switch(
                  value: uneven,
                  onChanged: (on) =>
                      _setSplitType(on ? SplitType.shares : SplitType.equal),
                ),
              ],
            ),
            if (uneven) ...[
              const SizedBox(height: 8),
              SegmentedButton<SplitType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: SplitType.shares, label: Text(l10n.splitShares)),
                  ButtonSegment(value: SplitType.percentage, label: Text('%')),
                  ButtonSegment(
                      value: SplitType.exact, label: Text(l10n.amount)),
                ],
                selected: {_splitType},
                onSelectionChanged: (s) => _setSplitType(s.first),
              ),
              const SizedBox(height: 16),
              for (final member in _active)
                _buildMemberSplitRow(member, currencyCode, l10n),
              _buildSplitSumIndicator(currencyCode),
            ],
          ],
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: MemberAvatar(member: member, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(member.name, overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              textAlign: TextAlign.end,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _splitType == SplitType.percentage ||
                    (_splitType == SplitType.exact &&
                        currencyHasDecimals(currencyCode)),
              ),
              style: const TextStyle(fontFeatures: tabularFigures),
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
    final cs = Theme.of(context).colorScheme;
    final color = isValid ? context.money.positive : cs.error;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(isValid ? Icons.check_circle : Icons.info_outline,
              size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitSumIndicator(String currencyCode) {
    final l10n = AppLocalizations.of(context)!;
    final active = _active;
    if (_splitType == SplitType.percentage) {
      final totalScaled = active.fold<int>(0, (sum, m) {
        final t = _splitControllers[m.id]?.text ?? '0';
        return sum + (_parsePercentScaled(t) ?? 0);
      });
      return _buildSumRow(
        totalScaled == 10000,
        l10n.splitSumPercentage((totalScaled / 100).toStringAsFixed(2)),
      );
    }
    if (_splitType == SplitType.exact) {
      final totalEntered = active.fold<int>(0, (sum, m) {
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

/// Live thousands grouping for zero-decimal currencies (VND: `1.250.000`),
/// so long amounts can be read while typing. Decimal currencies keep free
/// input limited to digits and one separator.
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter(this.currencyCode);

  final String currencyCode;

  static const _maxDigits = 12;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (currencyHasDecimals(currencyCode)) {
      final ok = RegExp(r'^\d{0,12}([.,]\d{0,2})?$').hasMatch(newValue.text);
      return ok ? newValue : oldValue;
    }

    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > _maxDigits) return oldValue;
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed.isEmpty) return const TextEditingValue();

    // Keep the caret after the same number of digits it was after.
    final caret = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCaret = newValue.text
        .substring(0, caret)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, trimmed.length);
    final leadingDropped = digits.length - trimmed.length;

    final buf = StringBuffer();
    var offset = 0;
    var seen = 0;
    final target =
        (digitsBeforeCaret - leadingDropped).clamp(0, trimmed.length);
    for (var i = 0; i < trimmed.length; i++) {
      if (i > 0 && (trimmed.length - i) % 3 == 0) buf.write('.');
      buf.write(trimmed[i]);
      seen++;
      if (seen == target) offset = buf.length;
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: target == 0 ? 0 : offset),
    );
  }
}

/// Horizontal row of member avatars to pick one (payer) or several
/// (participants).
class _MemberPicker extends StatelessWidget {
  const _MemberPicker({
    required this.members,
    required this.isSelected,
    required this.onTap,
    required this.meLabel,
    this.showCheck = false,
  });

  final List<Member> members;
  final bool Function(Member) isSelected;
  final ValueChanged<Member> onTap;
  final String meLabel;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter - 4),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final m = members[i];
          final selected = isSelected(m);
          return Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(m);
              },
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              child: SizedBox(
                width: 68,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        MemberAvatar(member: m, size: 44, selected: selected),
                        if (showCheck && selected)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check_circle,
                                  size: 16, color: cs.onSurface),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.isMe ? '${m.name} $meLabel' : m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected ? cs.onSurface : cs.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MiniTextButton extends StatelessWidget {
  const _MiniTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Full-width primary action pinned above the keyboard.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gutter, 12, AppTheme.gutter, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onPressed, child: Text(label)),
          ),
        ),
      ),
    );
  }
}
