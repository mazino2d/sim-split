import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/members/update_member.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/member_initial.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';

const _currencies = ['VND', 'USD', 'EUR', 'SGD', 'THB'];

const _groupEmojiOptions = [
  '🍜',
  '✈️',
  '🏖️',
  '🎉',
  '🏠',
  '💼',
  '🎮',
  '🎵',
  '🚗',
  '🛒',
  '💊',
  '🏋️',
  '📚',
  '🍺',
  '💰',
  '🌏',
];

const _memberEmojiOptions = [
  '👨',
  '👩',
  '👧',
  '👦',
  '🧒',
  '👴',
  '👵',
  '🧔',
  '👨‍💼',
  '👩‍💼',
  '👨‍🍳',
  '👩‍🍳',
  '👨‍💻',
  '👩‍💻',
  '👨‍🏫',
  '👩‍🏫',
  '👨‍⚕️',
  '👩‍⚕️',
  '👨‍🎨',
  '👩‍🎨',
  '🤓',
  '😎',
  '🥳',
  '😴',
  '🤠',
  '👻',
  '🐼',
  '🐶',
];

// Draft model for pending (unsaved) members in create mode
class _MemberDraft {
  _MemberDraft() : controller = TextEditingController();
  final TextEditingController controller;
  String? emoji;
  void dispose() => controller.dispose();
}

class GroupFormScreen extends ConsumerStatefulWidget {
  const GroupFormScreen({super.key, this.editGroupId});

  final String? editGroupId;

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String _currency = 'VND';
  String? _emoji;
  int _colorValue = 0xFF1976D2;
  bool _isLoading = false;
  bool _isDirty = false;

  // ── "Tôi" (me) member ────────────────────────────────────────────────────
  final _meNameController = TextEditingController();
  String? _meEmoji;
  // Edit mode only — track the existing me member to update it
  String? _existingMeId;
  DateTime? _existingMeCreatedAt;
  int _existingMeAvatarColor = 0xFF1976D2;

  // ── Create mode — pending other members ─────────────────────────────────
  final List<_MemberDraft> _memberDrafts = [];
  final _newNameController = TextEditingController();
  final _newFocusNode = FocusNode();
  String? _newEmoji;

  /// Remembers "my" name so new groups start with it filled in.
  static const _myNameKey = 'my_member_name';

  // ── Edit mode — renames of existing members not yet persisted ───────────
  // Keyed by member id. Flushed on form save, and on dispose as a fallback so
  // a rename is never silently lost when the user navigates back.
  final Map<String, ({Member member, String name})> _pendingRenames = {};
  late final UpdateMember _updateMemberUseCase;

  bool get isEdit => widget.editGroupId != null;

  @override
  void initState() {
    super.initState();
    _updateMemberUseCase = ref.read(updateMemberProvider);
    _nameController = TextEditingController();
    _nameController.addListener(() => setState(() => _isDirty = true));
    _meNameController.addListener(() => setState(() => _isDirty = true));
    if (isEdit) {
      _loadExistingGroup();
    } else {
      _prefillMyName();
    }
  }

  Future<void> _prefillMyName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_myNameKey);
    if (!mounted || name == null || _meNameController.text.isNotEmpty) return;
    _meNameController.text = name;
    setState(() => _isDirty = false);
  }

  /// Moves the typed name into the member list and readies the field for the
  /// next person.
  void _addDraft() {
    final name = _newNameController.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.lightImpact();
    final draft = _MemberDraft()..emoji = _newEmoji;
    draft.controller.text = name;
    setState(() {
      _memberDrafts.add(draft);
      _newNameController.clear();
      _newEmoji = null;
      _isDirty = true;
    });
    _newFocusNode.requestFocus();
  }

  Future<void> _loadExistingGroup() async {
    final groupId = widget.editGroupId!;
    final group = await ref.read(groupDetailProvider(groupId).future);
    if (!mounted) return;

    // Load the isMe member
    final members = await ref.read(memberListProvider(groupId).future);
    final meM = members.where((m) => m.isMe).firstOrNull;

    setState(() {
      _nameController.text = group.name;
      _currency = group.currencyCode;
      _emoji = group.emoji;
      _colorValue = group.colorValue;

      if (meM != null) {
        _meNameController.text = meM.name;
        _meEmoji = meM.emoji;
        _existingMeId = meM.id;
        _existingMeCreatedAt = meM.createdAt;
        _existingMeAvatarColor = meM.avatarColorValue;
      }

      _isDirty = false;
    });
  }

  @override
  void dispose() {
    // Persist renames the user typed but never committed (no save, no
    // editing-complete). The State is gone, so failures cannot be surfaced.
    for (final pending in _pendingRenames.values) {
      final m = pending.member;
      unawaited(_updateMemberUseCase(UpdateMemberParams(
        id: m.id,
        groupId: m.groupId,
        name: pending.name,
        avatarColorValue: m.avatarColorValue,
        emoji: m.emoji,
        isMe: m.isMe,
        createdAt: m.createdAt,
      )));
    }
    _pendingRenames.clear();
    _nameController.dispose();
    _meNameController.dispose();
    _newNameController.dispose();
    _newFocusNode.dispose();
    for (final d in _memberDrafts) {
      d.dispose();
    }
    super.dispose();
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
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discardChanges),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _onPendingRename(Member member, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == member.name) {
      _pendingRenames.remove(member.id);
    } else {
      _pendingRenames[member.id] = (member: member, name: trimmed);
    }
  }

  /// Persists pending member renames. Returns the first failure, if any.
  Future<Failure?> _flushPendingRenames() async {
    final notifier = ref.read(memberProvider.notifier);
    for (final entry in _pendingRenames.entries.toList()) {
      final m = entry.value.member;
      final result = await notifier.updateMember(
        id: m.id,
        groupId: m.groupId,
        name: entry.value.name,
        avatarColorValue: m.avatarColorValue,
        emoji: m.emoji,
        isMe: m.isMe,
        createdAt: m.createdAt,
      );
      final failure = result.fold<Failure?>((f) => f, (_) => null);
      if (failure != null) return failure;
      _pendingRenames.remove(entry.key);
    }
    return null;
  }

  void _showFailure(ScaffoldMessengerState messenger, Failure failure) {
    final l10n = AppLocalizations.of(context)!;
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(failure, l10n))),
    );
  }

  Future<void> _save() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    final groupNotifier = ref.read(groupProvider.notifier);
    final memberNotifier = ref.read(memberProvider.notifier);

    if (isEdit) {
      // ── Edit mode ──────────────────────────────────────────────────────
      final groupId = widget.editGroupId!;
      var failure = (await groupNotifier.updateGroup(
        id: groupId,
        name: _nameController.text.trim(),
        currencyCode: _currency,
        emoji: _emoji,
        colorValue: _colorValue,
      ))
          .fold<Failure?>((f) => f, (_) => null);

      final meName = _meNameController.text.trim();
      if (failure == null && meName.isNotEmpty) {
        final meResult = _existingMeId != null
            ? await memberNotifier.updateMember(
                id: _existingMeId!,
                groupId: groupId,
                name: meName,
                avatarColorValue: _existingMeAvatarColor,
                emoji: _meEmoji,
                isMe: true,
                createdAt: _existingMeCreatedAt!,
              )
            // No me member yet — create one
            : await memberNotifier.addMember(
                groupId: groupId,
                name: meName,
                emoji: _meEmoji,
                isMe: true,
              );
        failure = meResult.fold<Failure?>(
          (f) => f,
          (me) {
            _existingMeId = me.id;
            _existingMeCreatedAt = me.createdAt;
            _existingMeAvatarColor = me.avatarColorValue;
            return null;
          },
        );
      }

      failure ??= await _flushPendingRenames();

      if (!mounted) return;
      setState(() => _isLoading = false);
      if (failure != null) {
        _showFailure(messenger, failure);
        return;
      }
      _isDirty = false;
      ref.invalidate(groupDetailProvider(groupId));
      context.pop();
    } else {
      // ── Create mode ────────────────────────────────────────────────────
      // A name typed but not yet added with + still counts.
      _addDraft();
      final createResult = await groupNotifier.createGroup(
        name: _nameController.text.trim(),
        currencyCode: _currency,
        emoji: _emoji,
        colorValue: _colorValue,
      );
      final groupId = createResult.fold<String?>((_) => null, (g) => g.id);
      if (groupId == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        createResult.fold((f) => _showFailure(messenger, f), (_) {});
        return;
      }

      // Add "me" member (required) and pending other members. The group
      // already exists, so on failure we still navigate to it (the user can
      // add missing members there) but report the problem.
      var failure = (await memberNotifier.addMember(
        groupId: groupId,
        name: _meNameController.text.trim(),
        emoji: _meEmoji,
        isMe: true,
      ))
          .fold<Failure?>((f) => f, (_) => null);

      for (final draft in _memberDrafts) {
        final name = draft.controller.text.trim();
        if (name.isEmpty) continue;
        final result = await memberNotifier.addMember(
          groupId: groupId,
          name: name,
          emoji: draft.emoji,
        );
        failure ??= result.fold<Failure?>((f) => f, (_) => null);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_myNameKey, _meNameController.text.trim());

      if (!mounted) return;
      if (failure != null) _showFailure(messenger, failure);
      _isDirty = false;
      // Routes are nested under '/', so this yields [GroupList, GroupDetail]
      // and Back from the detail returns to the list.
      context.go('/groups/$groupId');
    }
  }

  Future<void> _confirmDeleteGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteGroupConfirmTitle),
        content: Text(l10n.deleteGroupConfirmMessage(_nameController.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(groupProvider.notifier).deleteGroup(widget.editGroupId!);
    if (!mounted) return;
    result.fold(
      (f) => _showFailure(messenger, f),
      (_) {
        _isDirty = false;
        _pendingRenames.clear();
        context.go('/');
      },
    );
  }

  Future<void> _showEmojiPicker({
    required List<String> options,
    required String? currentEmoji,
    required void Function(String?) onSelected,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.chooseIcon,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (options == _groupEmojiOptions)
                  _EmojiCell(
                    emoji: null,
                    selected: currentEmoji == null,
                    onTap: () {
                      onSelected(null);
                      Navigator.pop(ctx);
                    },
                    child: Icon(Icons.block,
                        size: 22, color: Theme.of(ctx).colorScheme.outline),
                  ),
                for (final e in options)
                  _EmojiCell(
                    emoji: e,
                    selected: currentEmoji == e,
                    onTap: () {
                      onSelected(e);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Watching keeps the auto-dispose notifiers alive while the form is open.
    // Both watches must run on every build: if `||` short-circuited them once
    // `_isLoading` is true, Riverpod would dispose the notifiers mid-save and
    // the next `ref.read` inside them would throw, leaving the spinner forever.
    final groupSaving = ref.watch(groupProvider).isLoading;
    final memberSaving = ref.watch(memberProvider).isLoading;
    final saving = _isLoading || groupSaving || memberSaving;
    // Changing currency would corrupt existing expense amounts.
    final currencyLocked = isEdit &&
        (ref
                .watch(expenseListProvider(widget.editGroupId!))
                .value
                ?.isNotEmpty ??
            true);
    final otherCount = isEdit
        ? (ref
                .watch(memberListProvider(widget.editGroupId!))
                .value
                ?.where((m) => !m.isMe)
                .length ??
            0)
        : _memberDrafts.length;

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
          title: Text(isEdit ? l10n.editGroup : l10n.newGroup),
          actions: [
            if (isEdit)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.deleteGroup,
                onPressed: saving ? null : _confirmDeleteGroup,
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
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    // ── Icon + name ───────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gutter),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: _emoji != null
                                ? Text(_emoji!,
                                    style: const TextStyle(fontSize: 32))
                                : Icon(Icons.group_outlined,
                                    size: 28,
                                    color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _nameController,
                              autofocus: !isEdit,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              style: theme.textTheme.titleLarge,
                              decoration: InputDecoration(
                                hintText: l10n.groupNameHint,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? l10n.groupNameRequired
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EmojiStrip(
                      options: _groupEmojiOptions,
                      selected: _emoji,
                      onSelected: (e) => setState(() {
                        _emoji = e == _emoji ? null : e;
                        _isDirty = true;
                      }),
                    ),

                    // ── Currency ──────────────────────────────────────
                    SectionLabel(l10n.groupCurrency),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.gutter),
                        children: [
                          for (final c in {..._currencies, _currency})
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(c),
                                labelStyle: TextStyle(
                                  color: c == _currency
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                selected: c == _currency,
                                onSelected: currencyLocked
                                    ? null
                                    : (_) => setState(() {
                                          _currency = c;
                                          _isDirty = true;
                                        }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (currencyLocked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppTheme.gutter, 8, AppTheme.gutter, 0),
                        child: Text(
                          l10n.currencyLockedHint,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),

                    // ── You ───────────────────────────────────────────
                    SectionLabel(l10n.you),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gutter),
                      child: _MeRow(
                        nameController: _meNameController,
                        emoji: _meEmoji,
                        onEmojiTap: () => _showEmojiPicker(
                          options: _memberEmojiOptions,
                          currentEmoji: _meEmoji,
                          onSelected: (e) => setState(() {
                            _meEmoji = e;
                            _isDirty = true;
                          }),
                        ),
                        l10n: l10n,
                      ),
                    ),

                    // ── Other members ─────────────────────────────────
                    SectionLabel(
                      l10n.members,
                      trailing: otherCount == 0 ? null : Text('$otherCount'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gutter),
                      child: isEdit
                          ? _EditModeMembersSection(
                              groupId: widget.editGroupId!,
                              onPendingRename: _onPendingRename,
                              onRenameSaved: (memberId) =>
                                  _pendingRenames.remove(memberId),
                              onShowEmojiPicker: (current, onSelected) =>
                                  _showEmojiPicker(
                                options: _memberEmojiOptions,
                                currentEmoji: current,
                                onSelected: onSelected,
                              ),
                            )
                          : _CreateModeMembersSection(
                              drafts: _memberDrafts,
                              newNameController: _newNameController,
                              newFocusNode: _newFocusNode,
                              newEmoji: _newEmoji,
                              onNewEmojiTap: () => _showEmojiPicker(
                                options: _memberEmojiOptions,
                                currentEmoji: _newEmoji,
                                onSelected: (e) =>
                                    setState(() => _newEmoji = e),
                              ),
                              onAdd: _addDraft,
                              onDraftEmojiTap: (draft) => _showEmojiPicker(
                                options: _memberEmojiOptions,
                                currentEmoji: draft.emoji,
                                onSelected: (e) =>
                                    setState(() => draft.emoji = e),
                              ),
                              onDraftDelete: (draft) {
                                setState(() => _memberDrafts.remove(draft));
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => draft.dispose());
                              },
                            ),
                    ),
                  ],
                ),
              ),
              _BottomAction(
                label: isEdit ? l10n.save : l10n.createGroup,
                loading: saving,
                onPressed: saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

/// One-tap emoji choice for the group icon; tapping the selected one clears
/// it.
class _EmojiStrip extends StatelessWidget {
  const _EmojiStrip({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = options[i];
          final isSelected = e == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: e,
            excludeSemantics: true,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(e);
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? cs.surfaceContainerHighest : null,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? cs.onSurface : cs.outlineVariant,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(e, style: const TextStyle(fontSize: 22)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tappable emoji cell used in bottom-sheet pickers.
class _EmojiCell extends StatelessWidget {
  const _EmojiCell({
    required this.selected,
    required this.onTap,
    this.emoji,
    this.child,
  });
  final String? emoji;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: emoji ?? AppLocalizations.of(context)!.noIcon,
      excludeSemantics: true,
      child: Material(
        color:
            selected ? colorScheme.surfaceContainerHighest : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color:
                selected ? colorScheme.onSurface : colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child:
                  child ?? Text(emoji!, style: const TextStyle(fontSize: 24)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accessible circular tap target for avatar/emoji pickers.
class _AvatarTapTarget extends StatelessWidget {
  const _AvatarTapTarget({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.chooseIcon,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Neutral avatar for a person not saved yet: their emoji, else the initial
/// of the typed name, else a placeholder icon.
class _DraftAvatar extends StatelessWidget {
  const _DraftAvatar({required this.emoji, this.name = ''});

  final String? emoji;
  final String name;

  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: emoji != null
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.48))
          : trimmed.isNotEmpty
              ? Text(
                  nameInitial(trimmed),
                  style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                )
              : Icon(Icons.person_outline,
                  size: size * 0.5, color: cs.onSurfaceVariant),
    );
  }
}

/// Square icon button used at the end of member rows.
class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return filled
        ? IconButton.filled(
            icon: Icon(icon),
            tooltip: tooltip,
            onPressed: onPressed,
          )
        : IconButton(
            icon: Icon(icon),
            tooltip: tooltip,
            onPressed: onPressed,
          );
  }
}

/// Full-width primary action pinned above the keyboard.
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gutter, 12, AppTheme.gutter, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: cs.onPrimary,
                      ),
                    )
                  : Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

// ── "Tôi" row ─────────────────────────────────────────────────────────────────

class _MeRow extends StatelessWidget {
  const _MeRow({
    required this.nameController,
    required this.emoji,
    required this.onEmojiTap,
    required this.l10n,
  });

  final TextEditingController nameController;
  final String? emoji;
  final VoidCallback onEmojiTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AvatarTapTarget(
          onTap: onEmojiTap,
          child: ListenableBuilder(
            listenable: nameController,
            builder: (context, _) =>
                _DraftAvatar(emoji: emoji, name: nameController.text),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(hintText: l10n.yourName),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.youRequired : null,
          ),
        ),
      ],
    );
  }
}

// ── "Add a person" field ─────────────────────────────────────────────────────

/// Always-visible input for adding people. Enter or + adds the name, clears
/// the field and keeps focus so the next name can be typed straight away.
class _AddMemberField extends StatelessWidget {
  const _AddMemberField({
    required this.controller,
    required this.focusNode,
    required this.emoji,
    required this.onEmojiTap,
    required this.onAdd,
    this.busy = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? emoji;
  final VoidCallback onEmojiTap;
  final VoidCallback onAdd;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasText = controller.text.trim().isNotEmpty;
        return Row(
          children: [
            _AvatarTapTarget(
              onTap: onEmojiTap,
              child: _DraftAvatar(emoji: emoji, name: controller.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(hintText: l10n.addPersonHint),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            _RowIconButton(
              icon: Icons.add,
              tooltip: l10n.addMember,
              filled: true,
              onPressed: hasText && !busy ? onAdd : null,
            ),
          ],
        );
      },
    );
  }
}

// ── Edit mode: stream-backed member list (non-me) ────────────────────────────

class _EditModeMembersSection extends ConsumerStatefulWidget {
  const _EditModeMembersSection({
    required this.groupId,
    required this.onShowEmojiPicker,
    required this.onPendingRename,
    required this.onRenameSaved,
  });

  final String groupId;
  final void Function(String? current, void Function(String?) onSelected)
      onShowEmojiPicker;
  final void Function(Member member, String name) onPendingRename;
  final void Function(String memberId) onRenameSaved;

  @override
  ConsumerState<_EditModeMembersSection> createState() =>
      _EditModeMembersSectionState();
}

class _EditModeMembersSectionState
    extends ConsumerState<_EditModeMembersSection> {
  bool _savingNew = false;
  final _newNameController = TextEditingController();
  final _newFocusNode = FocusNode();
  String? _newEmoji;

  @override
  void dispose() {
    _newNameController.dispose();
    _newFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveNew() async {
    if (_savingNew) return;
    final name = _newNameController.text.trim();
    if (name.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingNew = true);
    final result = await ref.read(memberProvider.notifier).addMember(
          groupId: widget.groupId,
          name: name,
          emoji: _newEmoji,
        );
    if (!mounted) return;
    setState(() => _savingNew = false);
    result.fold(
      // Keep the typed name so the user can retry.
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) {
        HapticFeedback.lightImpact();
        setState(() {
          _newNameController.clear();
          _newEmoji = null;
        });
        _newFocusNode.requestFocus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final membersAsync = ref.watch(memberListProvider(widget.groupId));

    return membersAsync.when(
      data: (allMembers) {
        final others = allMembers.where((m) => !m.isMe).toList();
        return Column(
          children: [
            for (final member in others)
              _ExistingMemberRow(
                key: ValueKey('member-${member.id}'),
                member: member,
                onShowEmojiPicker: widget.onShowEmojiPicker,
                onPendingRename: widget.onPendingRename,
                onRenameSaved: widget.onRenameSaved,
              ),
            const SizedBox(height: 4),
            _AddMemberField(
              controller: _newNameController,
              focusNode: _newFocusNode,
              emoji: _newEmoji,
              busy: _savingNew,
              onEmojiTap: () => widget.onShowEmojiPicker(
                _newEmoji,
                (e) => setState(() => _newEmoji = e),
              ),
              onAdd: _saveNew,
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: AppLoadingWidget(),
      ),
      error: (e, _) => Text(failureMessage(e, l10n)),
    );
  }
}

// ── Create mode: local draft list ────────────────────────────────────────────

class _CreateModeMembersSection extends StatelessWidget {
  const _CreateModeMembersSection({
    required this.drafts,
    required this.newNameController,
    required this.newFocusNode,
    required this.newEmoji,
    required this.onNewEmojiTap,
    required this.onAdd,
    required this.onDraftEmojiTap,
    required this.onDraftDelete,
  });

  final List<_MemberDraft> drafts;
  final TextEditingController newNameController;
  final FocusNode newFocusNode;
  final String? newEmoji;
  final VoidCallback onNewEmojiTap;
  final VoidCallback onAdd;
  final void Function(_MemberDraft) onDraftEmojiTap;
  final void Function(_MemberDraft) onDraftDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final draft in drafts)
          _DraftMemberRow(
            key: ObjectKey(draft),
            draft: draft,
            onEmojiTap: () => onDraftEmojiTap(draft),
            onDelete: () => onDraftDelete(draft),
            l10n: l10n,
          ),
        const SizedBox(height: 4),
        _AddMemberField(
          controller: newNameController,
          focusNode: newFocusNode,
          emoji: newEmoji,
          onEmojiTap: onNewEmojiTap,
          onAdd: onAdd,
        ),
      ],
    );
  }
}

// ── Draft member row (create mode, already committed to local list) ───────────

class _DraftMemberRow extends StatelessWidget {
  const _DraftMemberRow({
    super.key,
    required this.draft,
    required this.onEmojiTap,
    required this.onDelete,
    required this.l10n,
  });

  final _MemberDraft draft;
  final VoidCallback onEmojiTap;
  final VoidCallback onDelete;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _AvatarTapTarget(
            onTap: onEmojiTap,
            child: ListenableBuilder(
              listenable: draft.controller,
              builder: (context, _) =>
                  _DraftAvatar(emoji: draft.emoji, name: draft.controller.text),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: draft.controller,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: l10n.memberName),
            ),
          ),
          const SizedBox(width: 8),
          _RowIconButton(
            icon: Icons.close,
            tooltip: l10n.removeMember,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Existing member row (edit mode) ──────────────────────────────────────────

class _ExistingMemberRow extends ConsumerStatefulWidget {
  const _ExistingMemberRow({
    super.key,
    required this.member,
    required this.onShowEmojiPicker,
    required this.onPendingRename,
    required this.onRenameSaved,
  });

  final Member member;
  final void Function(String? current, void Function(String?) onSelected)
      onShowEmojiPicker;
  final void Function(Member member, String name) onPendingRename;
  final void Function(String memberId) onRenameSaved;

  @override
  ConsumerState<_ExistingMemberRow> createState() => _ExistingMemberRowState();
}

class _ExistingMemberRowState extends ConsumerState<_ExistingMemberRow> {
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.name);
  }

  @override
  void didUpdateWidget(_ExistingMemberRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.name != widget.member.name) {
      _nameController.text = widget.member.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Name to persist: the typed name when non-empty, else the stored one.
  String get _effectiveName {
    final typed = _nameController.text.trim();
    return typed.isEmpty ? widget.member.name : typed;
  }

  Future<void> _update({required String name, required String? emoji}) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final member = widget.member;
    setState(() => _saving = true);
    final result = await ref.read(memberProvider.notifier).updateMember(
          id: member.id,
          groupId: member.groupId,
          name: name,
          avatarColorValue: member.avatarColorValue,
          emoji: emoji,
          isMe: member.isMe,
          createdAt: member.createdAt,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      // The rename stays pending in the parent form and is retried on save.
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) => widget.onRenameSaved(member.id),
    );
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name == widget.member.name) return;
    await _update(name: name, emoji: widget.member.emoji);
  }

  void _pickEmoji() {
    widget.onShowEmojiPicker(
      widget.member.emoji,
      (e) => _update(name: _effectiveName, emoji: e),
    );
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.deleteMemberConfirmTitle),
        content: Text(l10n.deleteMemberConfirmMessage(widget.member.name)),
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
    final memberId = widget.member.id;
    final result = await ref
        .read(memberProvider.notifier)
        .removeMember(memberId, widget.member.groupId);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      // Member is gone: drop any pending rename so it is not re-applied.
      (_) => widget.onRenameSaved(memberId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final member = widget.member;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _AvatarTapTarget(
            onTap: _pickEmoji,
            child: MemberAvatar(member: member, size: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: l10n.memberName),
              onChanged: (v) => widget.onPendingRename(member, v),
              onEditingComplete: _saveName,
            ),
          ),
          const SizedBox(width: 8),
          // ✓ appears only while a rename is pending; otherwise remove.
          ListenableBuilder(
            listenable: _nameController,
            builder: (context, _) {
              final typed = _nameController.text.trim();
              final renamed = typed.isNotEmpty && typed != member.name;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: renamed
                    ? _RowIconButton(
                        key: const ValueKey('save'),
                        icon: Icons.check,
                        tooltip: l10n.save,
                        filled: true,
                        onPressed: _saving ? null : _saveName,
                      )
                    : _RowIconButton(
                        key: const ValueKey('remove'),
                        icon: Icons.close,
                        tooltip: l10n.removeMember,
                        onPressed: _confirmDelete,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
