import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'package:simsplit/presentation/utils/member_initial.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

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
  bool _addingNew = false;
  final _newNameController = TextEditingController();
  String? _newEmoji;

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
    if (isEdit) _loadExistingGroup();
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
    final colorScheme = Theme.of(context).colorScheme;
    // Watching keeps the auto-dispose notifiers alive while the form is open.
    final saving = _isLoading ||
        ref.watch(groupProvider).isLoading ||
        ref.watch(memberProvider).isLoading;
    // Changing currency would corrupt existing expense amounts.
    final currencyLocked = isEdit &&
        (ref
                .watch(expenseListProvider(widget.editGroupId!))
                .value
                ?.isNotEmpty ??
            true);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        if (canLeave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? l10n.editGroup : l10n.createGroup),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: l10n.save,
              onPressed: saving ? null : _save,
            ),
          ],
        ),
        body: _isLoading
            ? const AppLoadingWidget()
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Group icon + name (inline) ─────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: l10n.chooseIcon,
                          child: InkWell(
                            onTap: () => _showEmojiPicker(
                              options: _groupEmojiOptions,
                              currentEmoji: _emoji,
                              onSelected: (e) => setState(() {
                                _emoji = e;
                                _isDirty = true;
                              }),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: _emoji != null
                                    ? Text(_emoji!,
                                        style: const TextStyle(fontSize: 26))
                                    : Icon(Icons.add_photo_alternate_outlined,
                                        size: 24,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: l10n.groupName,
                              hintText: l10n.groupNameHint,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l10n.groupNameRequired
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Currency ───────────────────────────────────────
                    DropdownButtonFormField<String>(
                      // Re-create when the loaded group's currency arrives.
                      key: ValueKey('currency-$_currency'),
                      initialValue: _currency,
                      decoration: InputDecoration(
                        labelText: l10n.groupCurrency,
                        helperText:
                            currencyLocked ? l10n.currencyLockedHint : null,
                      ),
                      items: {..._currencies, _currency}
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: currencyLocked
                          ? null
                          : (v) => setState(() {
                                if (v == null) return;
                                _currency = v;
                                _isDirty = true;
                              }),
                    ),
                    const SizedBox(height: 28),

                    // ── "Tôi" section (always shown) ───────────────────
                    _SectionHeader(
                      icon: Icons.person,
                      label: l10n.you,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    _MeRow(
                      nameController: _meNameController,
                      emoji: _meEmoji,
                      onEmojiTap: () => _showEmojiPicker(
                        options: _memberEmojiOptions,
                        currentEmoji: _meEmoji,
                        onSelected: (e) => setState(() => _meEmoji = e),
                      ),
                      l10n: l10n,
                    ),
                    const SizedBox(height: 28),

                    // ── Other members ──────────────────────────────────
                    _SectionHeader(
                      icon: Icons.group_outlined,
                      label: l10n.members,
                    ),
                    const SizedBox(height: 8),

                    if (isEdit)
                      // Edit mode: stream-backed member list (non-me)
                      _EditModeMembersSection(
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
                    else
                      // Create mode: local draft list
                      _CreateModeMembersSection(
                        drafts: _memberDrafts,
                        addingNew: _addingNew,
                        newNameController: _newNameController,
                        newEmoji: _newEmoji,
                        onAddTap: () => setState(() {
                          _addingNew = true;
                          _newNameController.clear();
                          _newEmoji = null;
                        }),
                        onNewEmojiTap: () => _showEmojiPicker(
                          options: _memberEmojiOptions,
                          currentEmoji: _newEmoji,
                          onSelected: (e) => setState(() => _newEmoji = e),
                        ),
                        onNewSave: () {
                          final name = _newNameController.text.trim();
                          if (name.isEmpty) {
                            setState(() => _addingNew = false);
                            return;
                          }
                          final draft = _MemberDraft()..emoji = _newEmoji;
                          draft.controller.text = name;
                          setState(() {
                            _memberDrafts.add(draft);
                            _addingNew = false;
                            _isDirty = true;
                          });
                        },
                        onNewCancel: () => setState(() => _addingNew = false),
                        onDraftEmojiTap: (draft) => _showEmojiPicker(
                          options: _memberEmojiOptions,
                          currentEmoji: draft.emoji,
                          onSelected: (e) => setState(() => draft.emoji = e),
                        ),
                        onDraftDelete: (draft) {
                          draft.dispose();
                          setState(() => _memberDrafts.remove(draft));
                        },
                      ),

                    // ── Delete group (edit mode) ───────────────────────
                    if (isEdit) ...[
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                              foregroundColor: colorScheme.error),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.deleteGroup),
                          onPressed: saving ? null : _confirmDeleteGroup,
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
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: c,
                letterSpacing: 0.3)),
      ],
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
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
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

/// Lightweight icon tap button — no circular border.
class _FlatIconButton extends StatelessWidget {
  const _FlatIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: color),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AvatarTapTarget(
          onTap: onEmojiTap,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: emoji != null
                ? Text(emoji!, style: const TextStyle(fontSize: 20))
                : Icon(Icons.person,
                    size: 22, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: nameController,
            decoration: InputDecoration(
              hintText: l10n.yourName,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.youRequired : null,
          ),
        ),
      ],
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
  bool _addingNew = false;
  bool _savingNew = false;
  final _newNameController = TextEditingController();
  String? _newEmoji;

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _saveNew() async {
    if (_savingNew) return;
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _addingNew = false);
      return;
    }
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
      // Keep the row open with the typed name so the user can retry.
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) => setState(() {
        _addingNew = false;
        _newNameController.clear();
        _newEmoji = null;
      }),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add),
              label: Text(l10n.addMember),
              onPressed: () => setState(() {
                _addingNew = true;
                _newNameController.clear();
                _newEmoji = null;
              }),
            ),
            const SizedBox(height: 8),
            if (_addingNew) ...[
              _NewMemberRow(
                nameController: _newNameController,
                emoji: _newEmoji,
                onEmojiTap: () => widget.onShowEmojiPicker(
                  _newEmoji,
                  (e) => setState(() => _newEmoji = e),
                ),
                onSave: _saveNew,
                onCancel: () => setState(() => _addingNew = false),
                l10n: l10n,
              ),
              const SizedBox(height: 4),
            ],
            for (final member in others)
              _ExistingMemberRow(
                key: ValueKey('member-${member.id}'),
                member: member,
                onShowEmojiPicker: widget.onShowEmojiPicker,
                onPendingRename: widget.onPendingRename,
                onRenameSaved: widget.onRenameSaved,
              ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Text(failureMessage(e, l10n)),
    );
  }
}

// ── Create mode: local draft list ────────────────────────────────────────────

class _CreateModeMembersSection extends StatelessWidget {
  const _CreateModeMembersSection({
    required this.drafts,
    required this.addingNew,
    required this.newNameController,
    required this.newEmoji,
    required this.onAddTap,
    required this.onNewEmojiTap,
    required this.onNewSave,
    required this.onNewCancel,
    required this.onDraftEmojiTap,
    required this.onDraftDelete,
  });

  final List<_MemberDraft> drafts;
  final bool addingNew;
  final TextEditingController newNameController;
  final String? newEmoji;
  final VoidCallback onAddTap;
  final VoidCallback onNewEmojiTap;
  final VoidCallback onNewSave;
  final VoidCallback onNewCancel;
  final void Function(_MemberDraft) onDraftEmojiTap;
  final void Function(_MemberDraft) onDraftDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.person_add),
          label: Text(l10n.addMember),
          onPressed: onAddTap,
        ),
        const SizedBox(height: 8),
        if (addingNew) ...[
          _NewMemberRow(
            nameController: newNameController,
            emoji: newEmoji,
            onEmojiTap: onNewEmojiTap,
            onSave: onNewSave,
            onCancel: onNewCancel,
            l10n: l10n,
          ),
          const SizedBox(height: 4),
        ],
        for (final draft in drafts)
          _DraftMemberRow(
            draft: draft,
            onEmojiTap: () => onDraftEmojiTap(draft),
            onDelete: () => onDraftDelete(draft),
            l10n: l10n,
          ),
      ],
    );
  }
}

// ── New member row (being typed) ─────────────────────────────────────────────

class _NewMemberRow extends StatelessWidget {
  const _NewMemberRow({
    required this.nameController,
    required this.emoji,
    required this.onEmojiTap,
    required this.onSave,
    required this.onCancel,
    required this.l10n,
  });

  final TextEditingController nameController;
  final String? emoji;
  final VoidCallback onEmojiTap;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AvatarTapTarget(
          onTap: onEmojiTap,
          child: CircleAvatar(
            radius: 18,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: emoji != null
                ? Text(emoji!, style: const TextStyle(fontSize: 16))
                : Icon(Icons.person_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.addMemberName,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onFieldSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: 6),
        _FlatIconButton(
          icon: Icons.check,
          color: Theme.of(context).colorScheme.primary,
          onTap: onSave,
          tooltip: l10n.save,
        ),
        _FlatIconButton(
          icon: Icons.close,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          onTap: onCancel,
          tooltip: l10n.cancel,
        ),
      ],
    );
  }
}

// ── Draft member row (create mode, already committed to local list) ───────────

class _DraftMemberRow extends StatelessWidget {
  const _DraftMemberRow({
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _AvatarTapTarget(
            onTap: onEmojiTap,
            child: CircleAvatar(
              radius: 18,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              child: draft.emoji != null
                  ? Text(draft.emoji!, style: const TextStyle(fontSize: 16))
                  : Icon(Icons.person_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: draft.controller,
              decoration: InputDecoration(
                hintText: l10n.memberName,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FlatIconButton(
            icon: Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
            onTap: onDelete,
            tooltip: l10n.removeMember,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _AvatarTapTarget(
            onTap: _pickEmoji,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Color(member.avatarColorValue),
              child: member.emoji != null
                  ? Text(member.emoji!, style: const TextStyle(fontSize: 16))
                  : Text(
                      nameInitial(member.name),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: l10n.memberName,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => widget.onPendingRename(member, v),
              onEditingComplete: _saveName,
              onTapOutside: (_) => _saveName(),
            ),
          ),
          const SizedBox(width: 6),
          _FlatIconButton(
            icon: Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
            onTap: _confirmDelete,
            tooltip: l10n.removeMember,
          ),
        ],
      ),
    );
  }
}
