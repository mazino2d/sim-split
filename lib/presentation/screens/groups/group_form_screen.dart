import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

const _currencies = ['VND', 'USD', 'EUR', 'SGD', 'THB'];

const _emojiOptions = [
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
  int _colorValue = 0x00000000;
  bool _isLoading = false;

  bool get isEdit => widget.editGroupId != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    if (isEdit) _loadExistingGroup();
  }

  Future<void> _loadExistingGroup() async {
    final group =
        await ref.read(groupDetailProvider(widget.editGroupId!).future);
    if (!mounted) return;
    setState(() {
      _nameController.text = group.name;
      _currency = group.currencyCode;
      _emoji = group.emoji;
      _colorValue = group.colorValue;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteGroup(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final groupName = _nameController.text;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteGroupConfirmTitle),
        content: Text(l10n.deleteGroupConfirmMessage(groupName)),
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
    if (success && context.mounted) context.go('/');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final notifier = ref.read(groupNotifierProvider.notifier);
    bool success;

    if (isEdit) {
      success = await notifier.updateGroup(
        id: widget.editGroupId!,
        name: _nameController.text,
        currencyCode: _currency,
        emoji: _emoji,
        colorValue: _colorValue,
      );
    } else {
      success = await notifier.createGroup(
        name: _nameController.text,
        currencyCode: _currency,
        emoji: _emoji,
        colorValue: _colorValue,
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      if (isEdit) ref.invalidate(groupDetailProvider(widget.editGroupId!));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l10n.editGroup : l10n.createGroup),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteGroup,
              onPressed: () => _confirmDeleteGroup(context),
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
                  // Emoji picker
                  Wrap(
                    spacing: 8,
                    children: _emojiOptions.map((e) {
                      return ChoiceChip(
                        showCheckmark: false,
                        label: Text(e, style: const TextStyle(fontSize: 20)),
                        selected: _emoji == e,
                        onSelected: (_) =>
                            setState(() => _emoji = _emoji == e ? null : e),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Name field
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.groupName,
                      hintText: l10n.groupNameHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.groupNameRequired
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Currency dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: InputDecoration(
                      labelText: l10n.groupCurrency,
                      border: const OutlineInputBorder(),
                    ),
                    items: _currencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: _save,
                    child: Text(isEdit ? l10n.saveChanges : l10n.createGroup),
                  ),

                  // Members section — only in edit mode
                  if (isEdit) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      l10n.members,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    _MembersSection(groupId: widget.editGroupId!),
                  ],
                ],
              ),
            ),
    );
  }
}

class _MembersSection extends ConsumerWidget {
  const _MembersSection({required this.groupId});

  final String groupId;

  Future<void> _showMemberOptions(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.edit),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/groups/$groupId/members/${member.id}/edit',
                  extra: member,
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.person_remove_outlined, color: Colors.red),
              title:
                  Text(l10n.removeMember, style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmRemoveMember(context, ref, member);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveMember(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final l10n = AppLocalizations.of(context)!;
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
        .removeMember(member.id, groupId);

    if (!success && context.mounted) {
      final error = ref.read(memberNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error?.toString() ??
                AppLocalizations.of(context)!.cannotRemoveMemberWithDebts,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final membersAsync = ref.watch(memberListProvider(groupId));

    return membersAsync.when(
      data: (members) => Column(
        children: [
          for (final member in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(member.avatarColorValue),
                child: Text(
                  member.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(member.name),
              subtitle: member.isMe ? Text(l10n.markAsMe) : null,
              trailing: const Icon(Icons.more_vert),
              onTap: () => _showMemberOptions(context, ref, member),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add_outlined),
            title: Text(l10n.addMember),
            onTap: () => context.push('/groups/$groupId/members/add'),
          ),
        ],
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Text(e.toString()),
    );
  }
}
