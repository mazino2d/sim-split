import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/group.dart';
import '../../providers/group_providers.dart';

class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCount =
        ref.watch(memberListProvider(group.id)).valueOrNull?.length ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(group.colorValue),
          child: Text(
            group.emoji ?? group.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(fontSize: 18),
          ),
        ),
        title: Text(group.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$memberCount thành viên · ${group.currencyCode}',
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/groups/${group.id}'),
      ),
    );
  }
}
