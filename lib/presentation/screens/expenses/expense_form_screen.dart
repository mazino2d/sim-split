import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/money_formatter.dart';
import '../../../domain/entities/expense.dart';
import '../../../domain/entities/expense_split.dart';
import '../../../domain/entities/member.dart';
import '../../../domain/use_cases/expenses/calculate_splits.dart';
import '../../notifiers/expense_notifier.dart';
import '../../providers/expense_providers.dart';
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
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;
  String? _paidByMemberId;
  List<Member> _members = [];

  // Per-member split controllers and focus nodes
  final Map<String, TextEditingController> _splitControllers = {};
  final Map<String, FocusNode> _splitFocusNodes = {};
  // Snapshot of text when a field gains focus — used to revert if left empty
  final Map<String, String> _prevSplitTexts = {};

  bool _membersInitialized = false;
  bool _loadedExistingExpense = false;
  bool _isRedistributing = false;

  bool get isEdit => widget.editExpenseId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    for (final c in _splitControllers.values) c.dispose();
    for (final f in _splitFocusNodes.values) f.dispose();
    super.dispose();
  }

  // ── Initialization ────────────────────────────────────────────────────────

  void _initMemberControllers(List<Member> members) {
    if (_membersInitialized) return;
    _membersInitialized = true;
    _members = members;
    _paidByMemberId ??= members.isNotEmpty ? members.first.id : null;

    for (final m in members) {
      _splitControllers[m.id] = TextEditingController(text: '0');
      _splitFocusNodes[m.id] = FocusNode()
        ..addListener(() => _onFocusChanged(m.id));
    }
  }

  void _onFocusChanged(String memberId) {
    final focusNode = _splitFocusNodes[memberId]!;
    if (focusNode.hasFocus) {
      // Snapshot current value for revert
      _prevSplitTexts[memberId] = _splitControllers[memberId]?.text ?? '0';
      // Select all text so user can type over it immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctrl = _splitControllers[memberId];
        if (ctrl == null) return;
        ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      });
    } else {
      // Blur: revert if empty
      final ctrl = _splitControllers[memberId];
      if (ctrl != null && ctrl.text.trim().isEmpty) {
        setState(() {
          ctrl.text = _prevSplitTexts[memberId] ?? _defaultTextForType();
        });
      }
      // Redistribute remaining to other members
      if (_splitType == SplitType.percentage ||
          _splitType == SplitType.exact) {
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

    for (final split in expense.splits) {
      final ctrl = _splitControllers[split.memberId];
      if (ctrl == null) continue;
      ctrl.text = switch (expense.splitType) {
        SplitType.percentage =>
          (split.value / 100).toStringAsFixed(2), // 3333 → "33.33"
        SplitType.exact =>
          (split.amountCents ~/ 100).toString(), // cents → display
        SplitType.shares => split.value.toString(),
        SplitType.equal => '0',
      };
    }
  }

  // ── Default & Redistribute ────────────────────────────────────────────────

  /// Applies equal defaults for the current split type.
  void _applyDefaultSplits() {
    if (_members.isEmpty) return;
    final N = _members.length;
    final displayAmt = _parseDisplayAmount();

    setState(() {
      switch (_splitType) {
        case SplitType.percentage:
          final base = 10000 ~/ N; // scaled int
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

  /// After a member's field is edited (blur), redistribute remaining to others.
  void _redistributeAfterBlur(String changedMemberId) {
    if (_isRedistributing || _members.length <= 1) return;
    _isRedistributing = true;

    try {
      final others =
          _members.where((m) => m.id != changedMemberId).toList();
      final M = others.length;

      if (_splitType == SplitType.percentage) {
        final changedText =
            _splitControllers[changedMemberId]?.text ?? '0.00';
        final changedVal =
            ((double.tryParse(changedText) ?? 0) * 100).round();
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
        final changedVal = int.tryParse(
                changedText.replaceAll(',', '').replaceAll('.', '')) ??
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
    final text =
        _amountController.text.replaceAll(',', '').replaceAll('.', '');
    return int.tryParse(text) ?? 0;
  }

  // ── Build RawSplitInputs ──────────────────────────────────────────────────

  List<RawSplitInput> _buildSplitInputs() {
    return _members.map((m) {
      final text = _splitControllers[m.id]?.text ?? '0';
      final int val;
      switch (_splitType) {
        case SplitType.percentage:
          // User enters "33.33" → internal 3333
          val = ((double.tryParse(text) ?? 0) * 100).round();
        case SplitType.exact:
          // User enters display amount (VND) → cents (* 100)
          val = (int.tryParse(
                      text.replaceAll(',', '').replaceAll('.', '')) ??
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

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paidByMemberId == null) return;

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
      );
    }

    if (!mounted) return;
    if (success) {
      context.pop();
    } else {
      final error = ref.read(expenseNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error?.toString() ?? 'Lỗi không xác định')),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final membersAsync = ref.watch(memberListProvider(widget.groupId));
    final expensesAsync =
        isEdit ? ref.watch(expenseListProvider(widget.groupId)) : null;

    if (groupAsync.isLoading || membersAsync.isLoading) {
      return const Scaffold(body: AppLoadingWidget());
    }
    if (groupAsync.hasError) {
      return Scaffold(
          body: Center(child: Text(groupAsync.error.toString())));
    }

    final group = groupAsync.requireValue;
    final members = membersAsync.valueOrNull ?? [];
    _initMemberControllers(members);

    // Pre-populate when editing
    if (isEdit && expensesAsync != null) {
      final expenses = expensesAsync.valueOrNull ?? [];
      final existing = expenses
          .where((e) => e.id == widget.editExpenseId)
          .firstOrNull;
      if (existing != null && !_loadedExistingExpense) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _loadExistingExpense(existing)));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa chi tiêu' : 'Thêm chi tiêu'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Title ──────────────────────────────────────────────────────
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

            // ── Amount ─────────────────────────────────────────────────────
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

            // ── Paid by ────────────────────────────────────────────────────
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

            // ── Split type ─────────────────────────────────────────────────
            const Text('Kiểu chia',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<SplitType>(
              segments: const [
                ButtonSegment(value: SplitType.equal, label: Text('Đều')),
                ButtonSegment(value: SplitType.percentage, label: Text('%')),
                ButtonSegment(
                    value: SplitType.exact, label: Text('Số tiền')),
                ButtonSegment(
                    value: SplitType.shares, label: Text('Tỉ lệ')),
              ],
              selected: {_splitType},
              onSelectionChanged: (s) {
                setState(() => _splitType = s.first);
                _applyDefaultSplits();
              },
            ),
            const SizedBox(height: 16),

            // ── Per-member inputs ──────────────────────────────────────────
            if (_splitType != SplitType.equal) ...[
              _buildSplitHeader(group.currencyCode),
              const SizedBox(height: 8),
              for (final member in members)
                _buildMemberSplitRow(member, group.currencyCode),
              const SizedBox(height: 8),
              _buildSplitSumIndicator(group.currencyCode),
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

  Widget _buildSplitHeader(String currencyCode) {
    return Text(
      switch (_splitType) {
        SplitType.percentage => 'Phần trăm (tổng = 100%)',
        SplitType.exact => 'Số tiền mỗi người ($currencyCode)',
        SplitType.shares => 'Tỉ lệ phần',
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
            child: Text(
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
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
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
                  SplitType.shares => 'phần',
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

  /// Shows a live sum for % and exact types so user sees if it balances.
  Widget _buildSplitSumIndicator(String currencyCode) {
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
              size: 16,
              color: isValid ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(
            'Tổng: ${total.toStringAsFixed(2)}%',
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
              size: 16,
              color: isValid ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(
            'Tổng: ${formatMoney(totalEntered * 100, currencyCode)} / ${formatMoney(target * 100, currencyCode)}',
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
