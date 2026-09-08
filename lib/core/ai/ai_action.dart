import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'ai_provider.dart';

/// The things a spoken command can create. One entry per tool in
/// `AiCommandSchema`; the wire name is what the model writes in `kind`.
enum AiActionKind {
  addExpense,
  addTask,
  addNote,
  addMedicine,
  logHabit,
  startFocus,
  setBudget,
  addLoan,
  addBill,
  createAccount,
  createCategory,
  logSymptom,
  addPerson,
  createHabit,
  createProject,
  createFolder,
}

extension AiActionKindX on AiActionKind {
  String get wire => switch (this) {
    AiActionKind.addExpense => 'add_expense',
    AiActionKind.addTask => 'add_task',
    AiActionKind.addNote => 'add_note',
    AiActionKind.addMedicine => 'add_medicine',
    AiActionKind.logHabit => 'log_habit',
    AiActionKind.startFocus => 'start_focus',
    AiActionKind.setBudget => 'set_budget',
    AiActionKind.addLoan => 'add_loan',
    AiActionKind.addBill => 'add_bill',
    AiActionKind.createAccount => 'create_account',
    AiActionKind.createCategory => 'create_category',
    AiActionKind.logSymptom => 'log_symptom',
    AiActionKind.addPerson => 'add_person',
    AiActionKind.createHabit => 'create_habit',
    AiActionKind.createProject => 'create_project',
    AiActionKind.createFolder => 'create_folder',
  };

  AppModule get module => switch (this) {
    AiActionKind.addExpense => AppModule.expenses,
    AiActionKind.addTask => AppModule.tasks,
    AiActionKind.addNote => AppModule.notes,
    AiActionKind.addMedicine => AppModule.medicine,
    AiActionKind.logHabit => AppModule.habits,
    AiActionKind.startFocus => AppModule.focus,
    AiActionKind.setBudget => AppModule.expenses,
    AiActionKind.addLoan => AppModule.expenses,
    AiActionKind.addBill => AppModule.expenses,
    AiActionKind.createAccount => AppModule.expenses,
    AiActionKind.createCategory => AppModule.expenses,
    AiActionKind.logSymptom => AppModule.medicine,
    AiActionKind.addPerson => AppModule.expenses,
    AiActionKind.createHabit => AppModule.habits,
    AiActionKind.createProject => AppModule.tasks,
    AiActionKind.createFolder => AppModule.notes,
  };

  String get label => switch (this) {
    AiActionKind.addExpense => 'Expense',
    AiActionKind.addTask => 'Task',
    AiActionKind.addNote => 'Note',
    AiActionKind.addMedicine => 'Medicine',
    AiActionKind.logHabit => 'Habit',
    AiActionKind.startFocus => 'Focus',
    AiActionKind.setBudget => 'Budget',
    AiActionKind.addLoan => 'Loan',
    AiActionKind.addBill => 'Bill',
    AiActionKind.createAccount => 'Account',
    AiActionKind.createCategory => 'Category',
    AiActionKind.logSymptom => 'Symptom',
    AiActionKind.addPerson => 'Person',
    AiActionKind.createHabit => 'Habit',
    AiActionKind.createProject => 'Project',
    AiActionKind.createFolder => 'Folder',
  };

  HugeIconData get icon => switch (this) {
    AiActionKind.addExpense => AppIcons.expenses,
    AiActionKind.addTask => AppIcons.tasks,
    AiActionKind.addNote => AppIcons.notes,
    AiActionKind.addMedicine => AppIcons.medicine,
    AiActionKind.logHabit => AppIcons.habits,
    AiActionKind.startFocus => AppIcons.focus,
    AiActionKind.setBudget => AppIcons.savings,
    AiActionKind.addLoan => AppIcons.transfer,
    AiActionKind.addBill => AppIcons.bills,
    AiActionKind.createAccount => AppIcons.bank,
    AiActionKind.createCategory => AppIcons.otherCategory,
    AiActionKind.logSymptom => AppIcons.symptom,
    AiActionKind.addPerson => AppIcons.personAdd,
    AiActionKind.createHabit => AppIcons.habits,
    AiActionKind.createProject => AppIcons.folderSpecial,
    AiActionKind.createFolder => AppIcons.folder,
  };

  /// A method, not a getter: the accent lives in the theme and this file has
  /// no context, the same shape as `ResultKind.color`.
  Color color(BrandColors brand) => switch (this) {
    AiActionKind.addExpense => brand.expense,
    AiActionKind.addTask => brand.task,
    AiActionKind.addNote => brand.note,
    AiActionKind.addMedicine => brand.medicine,
    AiActionKind.logHabit => brand.habit,
    AiActionKind.startFocus => brand.focus,
    AiActionKind.setBudget => brand.expense,
    AiActionKind.addLoan => brand.expense,
    AiActionKind.addBill => brand.expense,
    AiActionKind.createAccount => brand.expense,
    AiActionKind.createCategory => brand.expense,
    AiActionKind.logSymptom => brand.medicine,
    AiActionKind.addPerson => brand.expense,
    AiActionKind.createHabit => brand.habit,
    AiActionKind.createProject => brand.task,
    AiActionKind.createFolder => brand.note,
  };

  static AiActionKind? fromWire(String? wire) =>
      AiActionKind.values.where((k) => k.wire == wire).firstOrNull;
}

/// What the model (or the offline parser) understood, before any name has
/// been matched against the database. Names stay strings here; the executor
/// turns them into ids and says what it could not find.
sealed class AiAction {
  const AiAction();

  AiActionKind get kind;
}

final class AddExpenseAction extends AiAction {
  final double amount;

  /// A `TxKind` value: expense or income. Transfers are not parsed from
  /// speech because they need two accounts and a direction.
  final int txKind;
  final String? category;
  final String? account;
  final String? person;
  final String? note;
  final DateTime? date;

  const AddExpenseAction({
    required this.amount,
    this.txKind = 0,
    this.category,
    this.account,
    this.person,
    this.note,
    this.date,
  });

  @override
  AiActionKind get kind => AiActionKind.addExpense;
}

final class AddTaskAction extends AiAction {
  final String title;
  final DateTime? dueDate;
  final bool hasTime;
  final DateTime? reminder;
  final int priority;
  final String? recurrence;
  final List<String> tags;
  final String? project;

  const AddTaskAction({
    required this.title,
    this.dueDate,
    this.hasTime = false,
    this.reminder,
    this.priority = 4,
    this.recurrence,
    this.tags = const [],
    this.project,
  });

  @override
  AiActionKind get kind => AiActionKind.addTask;
}

final class AddNoteAction extends AiAction {
  final String title;
  final String body;
  final DateTime? reminder;
  final List<String> tags;

  const AddNoteAction({
    required this.title,
    this.body = '',
    this.reminder,
    this.tags = const [],
  });

  @override
  AiActionKind get kind => AiActionKind.addNote;
}

final class AddMedicineAction extends AiAction {
  final String name;
  final String? form;
  final double? dosage;
  final String? dosageUnit;
  final int? timesPerDay;

  /// Minutes from midnight, the same unit as `Medicines.doseTimes`.
  final List<int>? doseMinutes;
  final int? days;
  final String? mealRelation;
  final String? person;
  final String? notes;

  const AddMedicineAction({
    required this.name,
    this.form,
    this.dosage,
    this.dosageUnit,
    this.timesPerDay,
    this.doseMinutes,
    this.days,
    this.mealRelation,
    this.person,
    this.notes,
  });

  @override
  AiActionKind get kind => AiActionKind.addMedicine;
}

final class LogHabitAction extends AiAction {
  final String habit;
  final double amount;

  const LogHabitAction({required this.habit, this.amount = 1});

  @override
  AiActionKind get kind => AiActionKind.logHabit;
}

final class StartFocusAction extends AiAction {
  final int minutes;

  const StartFocusAction({this.minutes = 25});

  @override
  AiActionKind get kind => AiActionKind.startFocus;
}

final class SetBudgetAction extends AiAction {
  final String? category;
  final double amount;

  const SetBudgetAction({this.category, required this.amount});

  @override
  AiActionKind get kind => AiActionKind.setBudget;
}

final class AddLoanAction extends AiAction {
  final String person;
  final double amount;
  final int direction;
  final String? account;
  final String? note;
  final DateTime? dueDate;

  const AddLoanAction({
    required this.person,
    required this.amount,
    required this.direction,
    this.account,
    this.note,
    this.dueDate,
  });

  @override
  AiActionKind get kind => AiActionKind.addLoan;
}

final class AddBillAction extends AiAction {
  final String title;
  final double amount;
  final String period;
  final int interval;
  final String? category;
  final String? account;
  final String? note;
  final DateTime? nextDueDate;

  const AddBillAction({
    required this.title,
    required this.amount,
    this.period = 'monthly',
    this.interval = 1,
    this.category,
    this.account,
    this.note,
    this.nextDueDate,
  });

  @override
  AiActionKind get kind => AiActionKind.addBill;
}

final class CreateAccountAction extends AiAction {
  final String name;

  const CreateAccountAction({required this.name});

  @override
  AiActionKind get kind => AiActionKind.createAccount;
}

final class CreateCategoryAction extends AiAction {
  final String name;
  final bool isIncome;

  const CreateCategoryAction({required this.name, this.isIncome = false});

  @override
  AiActionKind get kind => AiActionKind.createCategory;
}


final class LogSymptomAction extends AiAction {
  final String symptom;
  final int severity;
  final String? person;
  final String? note;

  const LogSymptomAction({
    required this.symptom,
    this.severity = 3,
    this.person,
    this.note,
  });

  @override
  AiActionKind get kind => AiActionKind.logSymptom;
}

final class AddPersonAction extends AiAction {
  final String name;
  final String relation;

  const AddPersonAction({required this.name, this.relation = 'Family'});

  @override
  AiActionKind get kind => AiActionKind.addPerson;
}

final class CreateHabitAction extends AiAction {
  final String name;

  const CreateHabitAction({required this.name});

  @override
  AiActionKind get kind => AiActionKind.createHabit;
}

final class CreateProjectAction extends AiAction {
  final String name;

  const CreateProjectAction({required this.name});

  @override
  AiActionKind get kind => AiActionKind.createProject;
}

final class CreateFolderAction extends AiAction {
  final String name;

  const CreateFolderAction({required this.name});

  @override
  AiActionKind get kind => AiActionKind.createFolder;
}

/// Who produced a result, so the screen can badge it honestly.
sealed class AiSource {
  const AiSource();

  String get label;
}

final class RemoteSource extends AiSource {
  final AiProvider provider;
  final String model;

  const RemoteSource(this.provider, this.model);

  @override
  String get label => '${provider.label} · $model';
}

final class OfflineSource extends AiSource {
  const OfflineSource();

  @override
  String get label => 'Offline parser';
}

@immutable
class AiCommandResult {
  final List<AiAction> actions;

  /// One sentence from the model, shown above the cards. Usually empty.
  final String reply;

  /// True when the model could not fill a required field (an amount, a
  /// name); the screen then keeps the transcript editable instead of saving.
  final bool needsClarification;
  final AiSource source;

  const AiCommandResult({
    required this.actions,
    this.reply = '',
    this.needsClarification = false,
    required this.source,
  });
}

/// Shared date formatting for prompts and parsers, kept next to the actions
/// so both sides of the wire agree on it.
class AiDates {
  const AiDates._();

  static String date(DateTime d) => Fmt.iso(Fmt.dateOnly(d));

  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String dateTime(DateTime d) => '${date(d)}T${time(d)}';

  /// Parses `HH:mm` into minutes from midnight; null when malformed.
  static int? minutesOf(String? hhmm) {
    if (hhmm == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }
}
