import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' show Either, Unit, unit;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/presentation/notifiers/invite_notifier.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';

/// Where an invite link lands (R-3 AC10, AC11). Opening it joins the group;
/// once the group has synced to this device, the friend picks their name
/// from the unclaimed members, or adds a new one, and lands in the group.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  String? _groupId;
  Failure? _failure;
  bool _addingName = false;
  bool _saving = false;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The app may have started on this screen from the link.
      FlutterNativeSplash.remove();
      _join();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _failure = null);
    final result =
        await ref.read(inviteProvider.notifier).joinGroup(widget.token);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _failure = failure),
      (groupId) => setState(() => _groupId = groupId),
    );
  }

  Future<void> _claim(Member member) async {
    setState(() => _saving = true);
    final result = await ref.read(memberProvider.notifier).updateMember(
          id: member.id,
          groupId: member.groupId,
          name: member.name,
          avatarColorValue: member.avatarColorValue,
          emoji: member.emoji,
          isMe: true,
          createdAt: member.createdAt,
        );
    _finish(result.map((_) => unit));
  }

  Future<void> _addMe() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final result = await ref
        .read(memberProvider.notifier)
        .addMember(groupId: _groupId!, name: name, isMe: true);
    _finish(result.map((_) => unit));
  }

  void _finish(Either<Failure, Unit> result) {
    if (!mounted) return;
    result.fold(
      (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(failureMessage(failure, AppLocalizations.of(context)!))));
      },
      (_) => context.go('/groups/$_groupId'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinGroupTitle)),
      body: SafeArea(child: _body(context, l10n)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final failure = _failure;
    if (failure != null) {
      return _Message(
        text: failureMessage(failure, l10n),
        actions: [
          FilledButton(onPressed: _join, child: Text(l10n.retry)),
          TextButton(
            onPressed: () => context.go('/'),
            child: Text(l10n.goToMyGroups),
          ),
        ],
      );
    }

    final groupId = _groupId;
    final group =
        groupId == null ? null : ref.watch(liveGroupProvider(groupId)).value;
    final members =
        groupId == null ? null : ref.watch(memberListProvider(groupId)).value;
    // Joining, then waiting for the group to arrive from the cloud.
    if (group == null || members == null || members.isEmpty) {
      return _Message(
        text: l10n.joiningGroup,
        leading: const CircularProgressIndicator(),
      );
    }
    // Already claimed a name here (e.g. the link opened twice).
    if (members.any((m) => m.isMe)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/groups/${group.id}');
      });
      return const SizedBox.shrink();
    }

    final unclaimed = members.where((m) => m.linkedUid == null).toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.gutter),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${group.emoji ?? ''} ${group.name}'.trim(),
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text(l10n.joinWhoAreYou, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.joinWhoAreYouHint,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final member in unclaimed)
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
            leading: MemberAvatar(member: member),
            title: Text(member.name),
            enabled: !_saving,
            onTap: () => _claim(member),
          ),
        if (!_addingName)
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
            leading: const Icon(Icons.person_add_alt_outlined),
            title: Text(l10n.notOnTheList),
            enabled: !_saving,
            onTap: () => setState(() => _addingName = true),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.gutter, 8, AppTheme.gutter, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.yourName,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _addMe(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saving ? null : _addMe,
                  child: Text(l10n.joinAsNewMember),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.leading, this.actions = const []});

  final String text;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(height: 16)],
              Text(text, textAlign: TextAlign.center),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                ...actions,
              ],
            ],
          ),
        ),
      );
}
