import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

const _avatarColors = [
  0xFF1976D2,
  0xFF03DAC6,
  0xFFFF6B6B,
  0xFF4CAF50,
  0xFF43A047,
  0xFFFF9800,
  0xFF9C27B0,
  0xFF795548,
];

class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({
    super.key,
    required this.groupId,
    this.editMember,
  });

  final String groupId;

  /// When set, the form is in edit mode and pre-fills from this member.
  final Member? editMember;

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late int _selectedColor;
  late bool _isMe;
  bool _isLoading = false;

  bool get _isEdit => widget.editMember != null;

  @override
  void initState() {
    super.initState();
    final m = widget.editMember;
    _nameController = TextEditingController(text: m?.name ?? '');
    _selectedColor = m?.avatarColorValue ?? _avatarColors[0];
    _isMe = m?.isMe ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    final notifier = ref.read(memberProvider.notifier);
    final m = widget.editMember;
    final result = m != null
        ? await notifier.updateMember(
            id: m.id,
            groupId: m.groupId,
            name: _nameController.text.trim(),
            avatarColorValue: _selectedColor,
            emoji: m.emoji,
            isMe: _isMe,
            createdAt: m.createdAt,
          )
        : await notifier.addMember(
            groupId: widget.groupId,
            name: _nameController.text.trim(),
            avatarColorValue: _selectedColor,
            isMe: _isMe,
          );

    if (!mounted) return;
    setState(() => _isLoading = false);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) => context.pop(),
    );
  }

  Future<void> _confirmDelete() async {
    if (_isLoading) return;
    final l10n = AppLocalizations.of(context)!;
    final member = widget.editMember!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.deleteMemberConfirmTitle),
        content: Text(l10n.deleteMemberConfirmMessage(member.name)),
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

    setState(() => _isLoading = true);
    final result = await ref
        .read(memberProvider.notifier)
        .removeMember(member.id, member.groupId);

    if (!mounted) return;
    setState(() => _isLoading = false);
    result.fold(
      (failure) => scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) => context.pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // Watching keeps the auto-dispose notifier alive while the screen is open.
    final saving = ref.watch(memberProvider).isLoading || _isLoading;
    final members = ref.watch(memberListProvider(widget.groupId)).value ?? [];

    // Find existing isMe member that is NOT the current member being edited
    final existingIsMeMember = members
        .where((m) => m.isMe && m.id != (widget.editMember?.id ?? ''))
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.editMember : l10n.addMember),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.removeMember,
              onPressed: saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Avatar color picker
            Wrap(
              spacing: 8,
              children: [
                for (final (index, color) in _avatarColors.indexed)
                  Semantics(
                    button: true,
                    selected: _selectedColor == color,
                    label: l10n.avatarColorOption(index + 1),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: _selectedColor == color
                              ? Border.all(
                                  color: colorScheme.onSurface, width: 3)
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.memberName,
                hintText: l10n.memberNameHint,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.memberNameRequired
                  : null,
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              title: Text(l10n.markAsMe),
              value: _isMe,
              onChanged: (v) => setState(() => _isMe = v),
            ),

            // Warning: another member is already marked as "me"
            if (_isMe && existingIsMeMember != null) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.tertiary),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: colorScheme.onTertiaryContainer, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.isMeWillReplace(existingIsMeMember.name),
                        style: TextStyle(
                          color: colorScheme.onTertiaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(_isEdit ? l10n.save : l10n.addMember),
            ),
          ],
        ),
      ),
    );
  }
}
