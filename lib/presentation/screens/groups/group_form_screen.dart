import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
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
  int _colorValue = 0xFF6200EE;
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
                ],
              ),
            ),
    );
  }
}
