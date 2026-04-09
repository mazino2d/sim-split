import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/use_cases/members/add_member.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

const _currencies = ['VND', 'USD', 'EUR', 'SGD', 'THB'];

const _groupEmojiOptions = [
  '🍜', '✈️', '🏖️', '🎉', '🏠', '💼', '🎮', '🎵',
  '🚗', '🛒', '💊', '🏋️', '📚', '🍺', '💰', '🌏',
];

const _memberEmojiOptions = [
  '👨', '👩', '👧', '👦', '🧒', '👴', '👵', '🧔',
  '👨‍💼', '👩‍💼', '👨‍🍳', '👩‍🍳', '👨‍💻', '👩‍💻',
  '👨‍🏫', '👩‍🏫', '👨‍⚕️', '👩‍⚕️', '👨‍🎨', '👩‍🎨',
  '🤓', '😎', '🥳', '😴', '🤠', '👻', '🐼', '🐶',
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

  bool get isEdit => widget.editGroupId != null;

  @override
  void initState() {
    super.initState();
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.discardChanges),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final notifier = ref.read(groupNotifierProvider.notifier);
    final addMember = ref.read(addMemberProvider);

    if (isEdit) {
      // ── Edit mode ──────────────────────────────────────────────────────
      final success = await notifier.updateGroup(
        id: widget.editGroupId!,
        name: _nameController.text.trim(),
        currencyCode: _currency,
        emoji: _emoji,
        colorValue: _colorValue,
      );

      // Save "me" member if we have one
      if (success && _existingMeId != null) {
        final meName = _meNameController.text.trim();
        if (meName.isNotEmpty) {
          await ref.read(memberNotifierProvider.notifier).updateMember(
                id: _existingMeId!,
                groupId: widget.editGroupId!,
                name: meName,
                avatarColorValue: _existingMeAvatarColor,
                emoji: _meEmoji,
                isMe: true,
                createdAt: _existingMeCreatedAt!,
              );
        }
      } else if (success && _existingMeId == null) {
        // No me member yet — create one
        final meName = _meNameController.text.trim();
        if (meName.isNotEmpty) {
          await addMember(AddMemberParams(
            groupId: widget.editGroupId!,
            name: meName,
            emoji: _meEmoji,
            isMe: true,
          ));
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      if (success) {
        _isDirty = false;
        ref.invalidate(groupDetailProvider(widget.editGroupId!));
        context.pop();
      }
    } else {
      // ── Create mode ────────────────────────────────────────────────────
      final groupId = await notifier.createGroup(
        name: _nameController.text.trim(),
        currencyCode: _currency,
        emoji: _emoji,
        colorValue: _colorValue,
      );

      if (groupId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Add "me" member (required)
      await addMember(AddMemberParams(
        groupId: groupId,
        name: _meNameController.text.trim(),
        emoji: _meEmoji,
        isMe: true,
      ));

      // Add pending other members
      for (final draft in _memberDrafts) {
        final name = draft.controller.text.trim();
        if (name.isNotEmpty) {
          await addMember(AddMemberParams(
            groupId: groupId,
            name: name,
            emoji: draft.emoji,
          ));
        }
      }

      if (!mounted) return;
      _isDirty = false;
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await ref
        .read(groupNotifierProvider.notifier)
        .deleteGroup(widget.editGroupId!);
    if (success && mounted) context.go('/');
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
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
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
                        size: 22,
                        color: Theme.of(ctx).colorScheme.outline),
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
              onPressed: _isLoading ? null : _save,
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
                                border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline),
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
                                            .outline),
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
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? l10n.groupNameRequired
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Currency ───────────────────────────────────────
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: InputDecoration(
                        labelText: l10n.groupCurrency,
                        border: const OutlineInputBorder(),
                      ),
                      items: _currencies
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _currency = v!;
                        _isDirty = true;
                      }),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),

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
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),

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
                          final draft = _MemberDraft()
                            ..emoji = _newEmoji;
                          draft.controller.text = name;
                          setState(() {
                            _memberDrafts.add(draft);
                            _addingNew = false;
                            _isDirty = true;
                          });
                        },
                        onNewCancel: () =>
                            setState(() => _addingNew = false),
                        onDraftEmojiTap: (draft) => _showEmojiPicker(
                          options: _memberEmojiOptions,
                          currentEmoji: draft.emoji,
                          onSelected: (e) =>
                              setState(() => draft.emoji = e),
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
                              foregroundColor: Colors.red),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.deleteGroup),
                          onPressed: _confirmDeleteGroup,
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
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15, color: c)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: child ??
              Text(emoji!, style: const TextStyle(fontSize: 24)),
        ),
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
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 20, color: color),
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
        GestureDetector(
          onTap: onEmojiTap,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: emoji != null
                ? Text(emoji!, style: const TextStyle(fontSize: 20))
                : Icon(Icons.person,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: nameController,
            decoration: InputDecoration(
              hintText: l10n.yourName,
              border: const OutlineInputBorder(),
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
  });

  final String groupId;
  final void Function(String? current, void Function(String?) onSelected)
      onShowEmojiPicker;

  @override
  ConsumerState<_EditModeMembersSection> createState() =>
      _EditModeMembersSectionState();
}

class _EditModeMembersSectionState
    extends ConsumerState<_EditModeMembersSection> {
  bool _addingNew = false;
  final _newNameController = TextEditingController();
  String? _newEmoji;

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _saveNew() async {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _addingNew = false);
      return;
    }
    final useCase = ref.read(addMemberProvider);
    await useCase(AddMemberParams(
      groupId: widget.groupId,
      name: name,
      emoji: _newEmoji,
    ));
    if (!mounted) return;
    setState(() {
      _addingNew = false;
      _newNameController.clear();
      _newEmoji = null;
    });
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
                member: member,
                groupId: widget.groupId,
                onEmojiTap: () => widget.onShowEmojiPicker(
                  member.emoji,
                  (e) => ref
                      .read(memberNotifierProvider.notifier)
                      .updateMember(
                        id: member.id,
                        groupId: member.groupId,
                        name: member.name,
                        avatarColorValue: member.avatarColorValue,
                        emoji: e,
                        isMe: member.isMe,
                        createdAt: member.createdAt,
                      ),
                ),
              ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Text(e.toString()),
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
        GestureDetector(
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
              border: const OutlineInputBorder(),
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
          color: Colors.green.shade600,
          onTap: onSave,
        ),
        _FlatIconButton(
          icon: Icons.close,
          color: Colors.grey.shade500,
          onTap: onCancel,
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
          GestureDetector(
            onTap: onEmojiTap,
            child: CircleAvatar(
              radius: 18,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              child: draft.emoji != null
                  ? Text(draft.emoji!, style: const TextStyle(fontSize: 16))
                  : Icon(Icons.person_outline,
                      size: 18,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: draft.controller,
              decoration: InputDecoration(
                hintText: l10n.memberName,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FlatIconButton(
            icon: Icons.delete_outline,
            color: Colors.red.shade400,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Existing member row (edit mode) ──────────────────────────────────────────

class _ExistingMemberRow extends ConsumerStatefulWidget {
  const _ExistingMemberRow({
    required this.member,
    required this.groupId,
    required this.onEmojiTap,
  });

  final Member member;
  final String groupId;
  final VoidCallback onEmojiTap;

  @override
  ConsumerState<_ExistingMemberRow> createState() => _ExistingMemberRowState();
}

class _ExistingMemberRowState extends ConsumerState<_ExistingMemberRow> {
  late final TextEditingController _nameController;

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

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name == widget.member.name) return;
    await ref.read(memberNotifierProvider.notifier).updateMember(
          id: widget.member.id,
          groupId: widget.member.groupId,
          name: name,
          avatarColorValue: widget.member.avatarColorValue,
          emoji: widget.member.emoji,
          isMe: widget.member.isMe,
          createdAt: widget.member.createdAt,
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await ref
        .read(memberNotifierProvider.notifier)
        .removeMember(widget.member.id, widget.member.groupId);
    if (!success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.cannotRemoveMemberWithDebts)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final member = widget.member;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onEmojiTap,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Color(member.avatarColorValue),
              child: member.emoji != null
                  ? Text(member.emoji!,
                      style: const TextStyle(fontSize: 16))
                  : Text(
                      member.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: l10n.memberName,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              onEditingComplete: _saveName,
              onTapOutside: (_) => _saveName(),
            ),
          ),
          const SizedBox(width: 6),
          _FlatIconButton(
            icon: Icons.delete_outline,
            color: Colors.red.shade400,
            onTap: _confirmDelete,
          ),
        ],
      ),
    );
  }
}
