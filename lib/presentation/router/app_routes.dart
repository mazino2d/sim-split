abstract final class AppRoutes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const starting = '/starting';
  static const groupDetail = '/groups/:groupId';
  static const groupForm = '/groups/form';
  static const groupFormEdit = '/groups/:groupId/edit';
  static const addExpense = '/groups/:groupId/expenses/add';
  static const editExpense = '/groups/:groupId/expenses/:expenseId/edit';
  static const expenseDetail = '/groups/:groupId/expenses/:expenseId';
  static const addMember = '/groups/:groupId/members/add';
  static const settle = '/groups/:groupId/settle';
  static const shareSplit = '/groups/:groupId/share';
  static const join = '/join/:token';
  static const activity = '/groups/:groupId/activity';
  static const diagnostics = '/settings/diagnostics';
  static const notificationSettings = '/settings/notifications';
  static const notificationPause = '/settings/notifications/pause';
  static const notificationActivity = '/settings/notifications/activity';
  static const notificationSettle = '/settings/notifications/settle';
  static const notificationQuietHours = '/settings/notifications/quiet-hours';
  static const notificationGroups = '/settings/notifications/groups';
  static const groupNotifications = '/groups/:groupId/notifications';

  static String groupNotificationsOf(String groupId) =>
      '/groups/$groupId/notifications';
}
