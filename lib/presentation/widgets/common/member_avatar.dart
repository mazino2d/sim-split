import 'package:flutter/material.dart';

import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/utils/member_initial.dart';

/// Neutral round avatar: the member's emoji, or their initial.
///
/// [selected] draws an inverted (filled) avatar, used by pickers.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.member,
    this.size = 40,
    this.selected = false,
  });

  final Member member;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final emoji = member.emoji;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? cs.primary : cs.surfaceContainerHigh,
      ),
      child: emoji != null
          ? Text(emoji, style: TextStyle(fontSize: size * 0.48))
          : Text(
              nameInitial(member.name),
              style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurface,
              ),
            ),
    );
  }
}
