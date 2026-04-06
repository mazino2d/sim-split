abstract final class AppRoutes {
  static const home = '/';
  static const groupDetail = '/groups/:groupId';
  static const groupForm = '/groups/form';
  static const groupFormEdit = '/groups/:groupId/edit';
  static const addExpense = '/groups/:groupId/expenses/add';
  static const editExpense = '/groups/:groupId/expenses/:expenseId/edit';
  static const expenseDetail = '/groups/:groupId/expenses/:expenseId';
  static const addMember = '/groups/:groupId/members/add';
  static const debts = '/groups/:groupId/debts';
  static const settle = '/groups/:groupId/settle';
}
