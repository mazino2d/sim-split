/// Every name a breadcrumb or usage event can carry (R-4 AC3, AC8). One fixed
/// vocabulary, so no free text — names, amounts, IDs — can reach a report.
/// The prefix gives the kind: `tap`, `form`, `dialog`, `gesture` or `op`.
///
/// Screens are recorded by their route pattern instead (`/groups/:groupId`).
enum TelemetryEvent {
  // ── Taps ────────────────────────────────────────────────────────────────
  tapGoHome,
  tapRetry,
  tapDialogCancel,
  tapDialogConfirm,
  tapCloseForm,
  tapSignInGoogle,
  tapPrivacyPolicy,
  tapOpenSettings,
  tapOpenDiagnostics,
  tapLanguage,
  tapTheme,
  tapSignOut,
  tapDeleteAccount,
  tapErrorReportsSwitch,
  tapCopyReportId,
  tapNewGroup,
  tapOpenGroup,
  tapEditGroup,
  tapShareGroup,
  tapMenuActivity,
  tapMenuEdit,
  tapMenuResetLink,
  tapMenuLeave,
  tapOpenActivityEntry,
  tapPickEmoji,
  tapOpenEmojiPicker,
  tapPickCurrency,
  tapAddMember,
  tapRemoveDraftMember,
  tapSaveMemberName,
  tapRemoveMember,
  tapDeleteGroup,
  tapSaveGroup,
  tapAddExpense,
  tapOpenExpense,
  tapEditExpense,
  tapDeleteExpense,
  tapPickPayer,
  tapSelectAllParticipants,
  tapToggleParticipant,
  tapPickDate,
  tapPickCategory,
  tapSplitUneven,
  tapSplitType,
  tapSaveExpense,
  tapPickColor,
  tapToggleIsMe,
  tapDeleteMember,
  tapSaveMember,
  tapSettleDebt,
  tapSaveSettlement,
  tapClaimMember,
  tapAddMyName,
  tapSaveMyName,
  tapClaimMe,
  tapNotNow,

  // ── Forms ───────────────────────────────────────────────────────────────
  formGroupSubmitted,
  formGroupAbandoned,
  formExpenseSubmitted,
  formExpenseAbandoned,
  formMemberSubmitted,
  formMemberAbandoned,
  formSettlementSubmitted,
  formSettlementAbandoned,

  // ── Dialogs, sheets and menus ───────────────────────────────────────────
  dialogOpened,
  dialogClosed,

  // ── Gestures ────────────────────────────────────────────────────────────
  gestureSwipeEditExpense,
  gestureSwipeDeleteExpense,
  gestureSwipeDeleteSettlement,

  // ── Operations: one per use case, with result and duration ──────────────
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
  opStopSync,
  opSetErrorReports;

  /// The snake_case wire name, e.g. `op_create_group`.
  String get wireName => name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '_${m[0]!.toLowerCase()}',
      );

  BreadcrumbKind get kind => switch (name) {
        final n when n.startsWith('tap') => BreadcrumbKind.tap,
        final n when n.startsWith('form') => BreadcrumbKind.form,
        final n when n.startsWith('dialog') => BreadcrumbKind.dialog,
        final n when n.startsWith('gesture') => BreadcrumbKind.gesture,
        _ => BreadcrumbKind.op,
      };
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
