import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../notifiers/group_notifier.dart';
import '../../providers/group_providers.dart';
import '../../widgets/common/loading_widget.dart';

const _currencies = ['VND', 'USD', 'EUR', 'SGD', 'THB'];

const _emojiOptions = [
  '🍜', '✈️', '🏖️', '🎉', '🏠', '💼', '🎮', '🎵',
  '🚗', '🛒', '💊', '🏋️', '📚', '🍺', '💰', '🌏',
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
    final group = await ref
        .read(groupDetailProvider(widget.editGroupId!).future);
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
    if (success) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa nhóm' : 'Tạo nhóm'),
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
                    decoration: const InputDecoration(
                      labelText: 'Tên nhóm',
                      hintText: 'vd. Du lịch Đà Nẵng',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vui lòng nhập tên nhóm'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Currency dropdown
                  DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Đơn vị tiền tệ',
                      border: OutlineInputBorder(),
                    ),
                    items: _currencies
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: _save,
                    child: Text(isEdit ? 'Lưu thay đổi' : 'Tạo nhóm'),
                  ),
                ],
              ),
            ),
    );
  }
}
