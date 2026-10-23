/// Every name a breadcrumb or usage event can carry (R-4 AC3, AC8). One fixed
/// vocabulary, so no free text — names, amounts, IDs — can reach a report.
///
/// Screens are recorded by their route pattern instead (`/groups/:groupId`).
enum TelemetryEvent {
  // Operations: one per use case, recorded with their result and duration.
  opSignInWithGoogle,
  opSignOut,
  opDeleteAccount,
  opCreateGroup,
  opUpdateGroup,
  opDeleteGroup,
  opAddMember,
  opUpdateMember,
  opRemoveMember,
  opAddExpense,
  opEditExpense,
  opDeleteExpense,
  opSettleDebt,
  opDeleteSettlement,
  opJoinGroup,
  opLeaveGroup,
  opGetInviteLink,
  opResetInviteLink,
  opStartSync,
  opStopSync;

  /// The snake_case wire name, e.g. `op_create_group`.
  String get wireName => name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '_${m[0]!.toLowerCase()}',
      );
}

/// What kind of thing a breadcrumb records.
enum BreadcrumbKind { screen, tap, form, dialog, gesture, op }

/// One step that led up to an error (R-4 AC3).
class Breadcrumb {
  const Breadcrumb(
      {required this.time, required this.kind, required this.name});

  final DateTime time;
  final BreadcrumbKind kind;

  /// A route pattern for screens, a [TelemetryEvent.wireName] otherwise.
  final String name;
}
