import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/group.dart';
import '../../providers/group_providers.dart';
import '../../widgets/common/error_widget.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/groups/group_card.dart';

class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SimSplit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {/* TODO: settings */},
          ),
        ],
      ),
      body: groupsAsync.when(
        data: (groups) => _GroupListBody(groups: groups),
        loading: () => const AppLoadingWidget(),
        error: (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(groupListProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/groups/form'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _GroupListBody extends StatelessWidget {
  const _GroupListBody({required this.groups});

  final List<Group> groups;

  @override
  Widget build(BuildContext context) {
    final activeGroups = groups.where((g) => !g.isArchived).toList();

    if (activeGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Chưa có nhóm nào',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Nhấn + để tạo nhóm đầu tiên',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activeGroups.length,
      itemBuilder: (context, index) => GroupCard(group: activeGroups[index]),
    );
  }
}
