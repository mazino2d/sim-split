import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../domain/entities/member.dart';
import '../../../domain/use_cases/members/add_member.dart';
import '../../notifiers/member_notifier.dart';

const _avatarColors = [
  0xFF1976D2, 0xFF03DAC6, 0xFFFF6B6B, 0xFF4CAF50,
  0xFF43A047, 0xFFFF9800, 0xFF9C27B0, 0xFF795548,
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    bool success;
    if (_isEdit) {
      final m = widget.editMember!;
      success = await ref.read(memberNotifierProvider.notifier).updateMember(
            id: m.id,
            groupId: m.groupId,
            name: _nameController.text.trim(),
            avatarColorValue: _selectedColor,
            isMe: _isMe,
            createdAt: m.createdAt,
          );
    } else {
      final useCase = ref.read(addMemberProvider);
      final result = await useCase(AddMemberParams(
        groupId: widget.groupId,
        name: _nameController.text.trim(),
        avatarColorValue: _selectedColor,
        isMe: _isMe,
      ));
      success = result.isRight();
      if (!success && mounted) {
        result.fold(
          (failure) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.toString())),
          ),
          (_) {},
        );
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa thành viên' : 'Thêm thành viên'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Avatar color picker
            Wrap(
              spacing: 8,
              children: _avatarColors.map((color) {
                final selected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên thành viên',
                hintText: 'vd. Khôi',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên' : null,
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              title: const Text('Đây là tôi'),
              value: _isMe,
              onChanged: (v) => setState(() => _isMe = v),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isLoading ? null : _save,
              child: Text(_isEdit ? 'Lưu' : 'Thêm'),
            ),
          ],
        ),
      ),
    );
  }
}
