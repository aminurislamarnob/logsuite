import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/expenses/repository/expense_repository.dart';
import '../../presentation/expenses/utils/expense_voice_parser.dart';
import '../../presentation/focus/providers/focus_provider.dart';
import '../../presentation/habits/repository/habit_repository.dart';
import '../../presentation/medicine/repository/medicine_repository.dart';
import '../../presentation/medicine/utils/dose_reminders.dart';
import '../../presentation/medicine/utils/schedule_generator.dart';
import '../../presentation/notes/repository/note_repository.dart';
import '../../presentation/tasks/repository/task_repository.dart';
import '../database/app_database.dart';
import '../providers/database_provider.dart';
import '../people/people_repository.dart';
import '../services/notification_service.dart';
import '../settings/app_settings.dart';
import '../utils/formatters.dart';
import 'ai_action.dart';
import 'ai_client.dart';
import 'ai_drafts.dart';
import 'ai_request_context.dart';
import 'name_resolver.dart';

final aiCommandExecutorProvider = Provider<AiCommandExecutor>(
  (ref) => AiCommandExecutor(ref),
);

/// Turns actions into drafts, and drafts into rows.
///
/// [resolve] is pure over the request context: it matches names, picks
/// fallbacks and collects warnings, and never touches the database. [save]
/// writes through the same repositories the editor sheets use and schedules
/// notifications the way those sheets do, so a spoken entry is
/// indistinguishable from a typed one afterwards.
class AiCommandExecutor {
  AiCommandExecutor(this._ref);

  final Ref _ref;

  // --- Resolve -------------------------------------------------------------

  Future<List<ActionPreview>> resolve(
    List<AiAction> actions,
    AiRequestContext c,
  ) async {
    return [for (final a in actions) _resolveOne(a, c)];
  }

  ActionPreview _resolveOne(AiAction action, AiRequestContext c) {
    if (!c.isEnabled(action.kind.module)) {
      return ActionPreview(
        draft: _placeholder(action, c),
        warnings: ['${action.kind.module.label} is turned off in Settings'],
        blocked: true,
      );
    }
    return switch (action) {
      SetBudgetAction a => _budget(a, c),
      AddLoanAction a => _loan(a, c),
      AddBillAction a => _bill(a, c),
      CreateAccountAction a => ActionPreview(draft: CreateAccountDraft(title: a.name)),
      CreateCategoryAction a => ActionPreview(draft: CreateCategoryDraft(title: a.name, isIncome: a.isIncome)),
      LogSymptomAction a => _symptom(a, c),
      AddPersonAction a => ActionPreview(draft: AddPersonDraft(title: a.name, relation: a.relation)),
      CreateHabitAction a => ActionPreview(draft: CreateHabitDraft(title: a.name)),
      CreateProjectAction a => ActionPreview(draft: CreateProjectDraft(title: a.name)),
      CreateFolderAction a => ActionPreview(draft: CreateFolderDraft(title: a.name)),
      AddExpenseAction a => _expense(a, c),
      AddTaskAction a => _task(a, c),
      AddNoteAction a => ActionPreview(
        draft: NoteDraft(
          title: a.title,
          body: a.body,
          reminderAt: a.reminder,
          tags: a.tags,
        ),
      ),
      AddMedicineAction a => _medicine(a, c),
      LogHabitAction a => _habit(a, c),
      StartFocusAction a => ActionPreview(
        draft: FocusDraft(minutes: a.minutes.clamp(5, 180)),
        warnings: [
          if (a.minutes < 5 || a.minutes > 180)
            'Focus sessions run 5 to 180 minutes',
        ],
      ),
    };
  }

  ActionPreview _expense(AddExpenseAction a, AiRequestContext c) {
    final warnings = <String>[];
    final isIncome = a.txKind == TxKind.income;
    final pool = c.categories.where((x) => x.isIncome == isIncome).toList();

    final category = NameResolver.resolve(
      a.category,
      pool,
      (x) => [x.name],
      hints: isIncome ? const {} : ExpenseVoiceParser.categoryHints,
      haystack: [a.category, a.note].whereType<String>().join(' '),
    );
    var categoryRow = category?.item;
    if (categoryRow == null) {
      categoryRow = pool
          .where((x) => x.name.toLowerCase() == 'other')
          .firstOrNull;
      if (a.category != null) {
        warnings.add(
          'No category "${a.category}"'
          '${categoryRow == null ? '' : ' — using ${categoryRow.name}'}',
        );
      }
    }

    final account = NameResolver.resolve(
      a.account,
      c.accounts,
      (x) => [x.name, x.type],
    );
    var accountRow = account?.item;
    if (accountRow == null) {
      accountRow = c.accounts.firstOrNull;
      if (a.account != null && accountRow != null) {
        warnings.add('No account "${a.account}" — using ${accountRow.name}');
      }
    }
    if (accountRow == null) {
      return ActionPreview(
        draft: _placeholder(a, c),
        warnings: ['Add an account in Expenses first'],
        blocked: true,
      );
    }

    Person? personRow;
    if (a.person != null && !_meansSelf(a.person!)) {
      personRow = NameResolver.resolve(
        a.person,
        c.people,
        (p) => [p.name],
      )?.item;
      if (personRow == null) warnings.add('No one called "${a.person}"');
    }

    if (a.amount <= 0) {
      return ActionPreview(
        draft: _placeholder(a, c),
        warnings: ['The amount is missing'],
        blocked: true,
      );
    }

    return ActionPreview(
      draft: ExpenseDraft(
        amount: a.amount,
        txKind: a.txKind,
        categoryId: categoryRow?.id,
        categoryName: categoryRow?.name,
        accountId: accountRow.id,
        accountName: accountRow.name,
        personId: personRow?.id,
        personName: personRow?.name,
        note: a.note,
        date: a.date ?? c.now,
      ),
      warnings: warnings,
    );
  }


  ActionPreview _budget(SetBudgetAction a, AiRequestContext c) {
    final category = NameResolver.resolve(
      a.category,
      c.categories.where((x) => !x.isIncome).toList(),
      (x) => [x.name],
    );
    return ActionPreview(
      draft: SetBudgetDraft(
        categoryId: category?.item.id,
        categoryName: category?.item.name,
        amount: a.amount,
      ),
    );
  }

  ActionPreview _loan(AddLoanAction a, AiRequestContext c) {
    final person = NameResolver.resolve(
      a.person,
      c.people,
      (x) => [x.name],
    );
    final account = NameResolver.resolve(
      a.account,
      c.accounts,
      (x) => [x.name],
    );
    return ActionPreview(
      draft: AddLoanDraft(
        personId: person?.item.id,
        personName: person?.item.name,
        amount: a.amount,
        direction: a.direction,
        accountId: account?.item.id,
        accountName: account?.item.name,
        note: a.note,
        dueDate: a.dueDate,
      ),
      warnings: [
        if (person == null) 'No person "${a.person}" — default will be used',
      ],
    );
  }

  ActionPreview _bill(AddBillAction a, AiRequestContext c) {
    final category = NameResolver.resolve(
      a.category,
      c.categories.where((x) => !x.isIncome).toList(),
      (x) => [x.name],
    );
    final account = NameResolver.resolve(
      a.account,
      c.accounts,
      (x) => [x.name],
    );
    return ActionPreview(
      draft: AddBillDraft(
        title: a.title,
        amount: a.amount,
        period: a.period,
        interval: a.interval,
        categoryId: category?.item.id,
        categoryName: category?.item.name,
        accountId: account?.item.id,
        accountName: account?.item.name,
        note: a.note,
        nextDueDate: a.nextDueDate,
      ),
    );
  }

  ActionPreview _symptom(LogSymptomAction a, AiRequestContext c) {
    final person = NameResolver.resolve(
      a.person,
      c.people,
      (x) => [x.name],
    );
    return ActionPreview(
      draft: LogSymptomDraft(
        title: a.symptom,
        severity: a.severity,
        personId: person?.item.id,
        personName: person?.item.name,
        note: a.note,
      ),
      warnings: [
        if (person == null && a.person != null)
          'No person "${a.person}" — default will be used',
      ],
    );
  }

  ActionPreview _task(AddTaskAction a, AiRequestContext c) {
    final warnings = <String>[];
    Project? project;
    if (a.project != null) {
      project = NameResolver.resolve(
        a.project,
        c.projects,
        (p) => [p.name],
      )?.item;
      if (project == null) warnings.add('No project "${a.project}"');
    }
    if (a.reminder != null && a.reminder!.isBefore(c.now)) {
      warnings.add('The reminder time has already passed');
    }
    return ActionPreview(
      draft: TaskDraft(
        title: a.title,
        dueDate: a.dueDate,
        hasDueTime: a.hasTime,
        reminder: a.reminder,
        priority: a.priority.clamp(1, 4),
        recurrenceRule: a.recurrence,
        tags: a.tags,
        projectId: project?.id,
        projectName: project?.name,
      ),
      warnings: warnings,
    );
  }

  ActionPreview _medicine(AddMedicineAction a, AiRequestContext c) {
    final warnings = <String>[];
    Person? profile;
    if (a.person != null && !_meansSelf(a.person!)) {
      profile = NameResolver.resolve(
        a.person,
        c.profiles,
        (p) => [p.name],
      )?.item;
      if (profile == null) warnings.add('No profile called "${a.person}"');
    }
    profile ??= c.profiles.firstOrNull;

    final times =
        a.doseMinutes ?? ScheduleSpec.defaultTimesFor(a.timesPerDay ?? 1);
    final start = Fmt.dateOnly(c.now);
    final days = (a.days ?? 7).clamp(1, 365);
    if (a.days == null) warnings.add('No length given — assuming 7 days');
    final form = a.form ?? 'tablet';

    return ActionPreview(
      draft: MedicineDraft(
        name: a.name,
        form: form,
        dosage: a.dosage ?? 1,
        dosageUnit: a.dosageUnit ?? form,
        doseMinutes: times,
        start: start,
        end: start.add(Duration(days: days - 1)),
        meal: MealRelationX.fromToken(a.mealRelation ?? 'none'),
        profileId: profile?.id,
        profileName: profile?.name,
        notes: a.notes,
      ),
      warnings: warnings,
    );
  }

  ActionPreview _habit(LogHabitAction a, AiRequestContext c) {
    final habit = NameResolver.resolve(a.habit, c.habits, (h) => [h.name]);
    if (habit == null) {
      return ActionPreview(
        draft: HabitLogDraft(habitId: 0, habitName: a.habit, amount: a.amount),
        warnings: ['No habit called "${a.habit}"'],
        blocked: true,
      );
    }
    return ActionPreview(
      draft: HabitLogDraft(
        habitId: habit.item.id,
        habitName: habit.item.name,
        amount: a.amount <= 0 ? 1 : a.amount,
        unit: habit.item.unit,
      ),
      warnings: [
        if (!habit.exact) 'Matched "${a.habit}" to ${habit.item.name}',
      ],
    );
  }

  /// A draft that only exists to be shown on a blocked card.
  AiDraft _placeholder(AiAction action, AiRequestContext c) => switch (action) {
    AddExpenseAction a => ExpenseDraft(
      amount: a.amount,
      txKind: a.txKind,
      categoryName: a.category,
      accountId: 0,
      accountName: a.account ?? '',
      note: a.note,
      date: a.date ?? c.now,
    ),
    AddTaskAction a => TaskDraft(title: a.title, dueDate: a.dueDate),
    AddNoteAction a => NoteDraft(title: a.title, body: a.body),
    AddMedicineAction a => MedicineDraft(
      name: a.name,
      start: Fmt.dateOnly(c.now),
      end: Fmt.dateOnly(c.now),
    ),
    LogHabitAction a => HabitLogDraft(
      habitId: 0,
      habitName: a.habit,
      amount: a.amount,
    ),
    StartFocusAction a => FocusDraft(minutes: a.minutes),
    SetBudgetAction a => SetBudgetDraft(categoryName: a.category, amount: a.amount),
    AddLoanAction a => AddLoanDraft(amount: a.amount, direction: a.direction),
    AddBillAction a => AddBillDraft(title: a.title, amount: a.amount),
    CreateAccountAction a => CreateAccountDraft(title: a.name),
    CreateCategoryAction a => CreateCategoryDraft(title: a.name, isIncome: a.isIncome),
    LogSymptomAction a => LogSymptomDraft(title: a.symptom),
    AddPersonAction a => AddPersonDraft(title: a.name, relation: a.relation),
    CreateHabitAction a => CreateHabitDraft(title: a.name),
    CreateProjectAction a => CreateProjectDraft(title: a.name),
    CreateFolderAction a => CreateFolderDraft(title: a.name),

  };

  static bool _meansSelf(String name) => const {
    'me',
    'myself',
    'self',
    'i',
    'ami',
    'amar',
  }.contains(name.trim().toLowerCase());

  // --- Save ----------------------------------------------------------------

  /// Saves every draft in order. One failure does not abort the rest, and
  /// the outcome says which drafts were written and which were not, so the
  /// caller can mark the successes and retry only the failures. Throwing
  /// here would hide the rows that did land and invite a duplicate write.
  Future<AiSaveOutcome> saveAll(Iterable<AiDraft> drafts) async {
    final results = <SavedItem?>[];
    final failures = <String>[];
    for (final draft in drafts) {
      try {
        results.add(await save(draft));
      } on Exception catch (e) {
        debugPrint('Could not save ${draft.kind.wire}: $e');
        results.add(null);
        failures.add(
          '${draft.kind.label} "${draft.title}": '
          '${e is AiException ? e.message : 'could not be saved'}',
        );
      }
    }
    return AiSaveOutcome(results: results, failures: failures);
  }

  Future<SavedItem> save(AiDraft draft) async {
    final notifier = _ref.read(notificationServiceProvider);
    switch (draft) {
      case ExpenseDraft d:
        final id = await _ref
            .read(expenseRepositoryProvider)
            .addTransaction(
              amount: d.amount,
              accountId: d.accountId,
              categoryId: d.categoryId,
              kind: d.txKind,
              personId: d.personId,
              note: d.note,
              date: d.date,
            );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.expenses.route,
        );


      case SetBudgetDraft d:
        final id = await _ref.read(expenseRepositoryProvider).setBudget(
              month: DateTime(DateTime.now().year, DateTime.now().month, 1),
              amount: d.amount,
              categoryId: d.categoryId,
            );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.expenses.route,
        );

      case AddLoanDraft d:
        final id = await _ref.read(expenseRepositoryProvider).createLoan(
              personId: d.personId ?? 1,
              direction: d.direction,
              principal: d.amount,
              accountId: d.accountId ?? 1,
              note: d.note,
              dueDate: d.dueDate,
            );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.expenses.route,
        );

      case AddBillDraft d:
        final bill = await _ref.read(expenseRepositoryProvider).createRecurring(
          RecurringExpensesCompanion.insert(
            name: d.title,
            amount: d.amount,
            period: Value(d.period),
            accountId: Value(d.accountId),
            categoryId: Value(d.categoryId),
            nextDueDate: d.nextDueDate ?? DateTime.now(),
          )
        );
        return SavedItem(
          kind: d.kind,
          id: bill.id,
          title: d.title,
          route: AppModule.expenses.route,
        );

      case CreateAccountDraft d:
        final id = await _ref.read(expenseRepositoryProvider).createAccount(
          d.title,
          'other',
          0.0,
          0,
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.expenses.route,
        );

      case CreateCategoryDraft d:
        final id = await _ref.read(expenseRepositoryProvider).createCategory(
          d.title,
          'other',
          0,
          isIncome: d.isIncome,
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.expenses.route,
        );

      case LogSymptomDraft d:
        final id = await _ref.read(medicineRepositoryProvider).logSymptom(
          symptom: d.title,
          severity: d.severity,
          profileId: d.personId,
          note: d.note,
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.medicine.route,
        );

      case AddPersonDraft d:
        final id = await _ref.read(peopleRepositoryProvider).createPerson(
          name: d.title,
          relation: d.relation,
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.expenses.route,
        );

      case CreateHabitDraft d:
        final id = await _ref.read(habitRepositoryProvider).createHabit(
          HabitsCompanion.insert(
            name: d.title,
            icon: const Value('star'),
            color: const Value(0),
            goalType: const Value(0),
            targetAmount: const Value(1.0),
            frequencyType: const Value(0),
            weekdayMask: const Value(127),
            timesPerWeek: const Value(7),
            createdAt: Value(DateTime.now()),
          )
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.habits.route,
        );

      case CreateProjectDraft d:
        final id = await _ref.read(taskRepositoryProvider).createProject(
          d.title,
          0,
          'folder',
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.tasks.route,
        );

      case CreateFolderDraft d:
        final id = await _ref.read(noteRepositoryProvider).createFolder(
          d.title,
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.notes.route,
        );

      case TaskDraft d:
        final repo = _ref.read(taskRepositoryProvider);
        final id = await repo.createTask(
          title: d.title,
          description: d.description,
          dueDate: d.dueDate,
          hasDueTime: d.hasDueTime,
          reminderTime: d.reminder,
          priority: d.priority,
          projectId: d.projectId,
          recurrenceRule: d.recurrenceRule,
        );
        if (d.tags.isNotEmpty) await repo.setTaskTags(id, d.tags);
        if (d.reminder != null) {
          await _guarded(
            () => notifier.scheduleTaskReminder(
              taskId: id,
              title: d.title,
              when: d.reminder!,
            ),
          );
        }
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: AppModule.tasks.route,
        );

      case NoteDraft d:
        final repo = _ref.read(noteRepositoryProvider);
        final id = await repo.createNote(
          title: d.title,
          contentJson: NoteRepository.deltaFromPlainText(d.body),
        );
        if (d.tags.isNotEmpty) await repo.setNoteTags(id, d.tags);
        if (d.reminderAt != null) {
          await repo.updateNote(id, reminderAt: d.reminderAt);
          await _guarded(
            () => notifier.scheduleNoteReminder(
              noteId: id,
              title: d.title,
              when: d.reminderAt!,
            ),
          );
        }
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.title,
          route: '/note_editor',
          extra: id,
        );

      case MedicineDraft d:
        final repo = _ref.read(medicineRepositoryProvider);
        final id = await repo.createMedicineWithSchedule(
          medicine: MedicinesCompanion(
            name: Value(d.name),
            form: Value(d.form),
            dosage: Value(d.dosage),
            dosageUnit: Value(d.dosageUnit),
            notes: Value(d.notes),
            profileId: Value(d.profileId),
            frequencyType: Value(MedFrequency.timesPerDay.index),
            doseTimes: Value(ScheduleSpec.encodeTimes(d.doseMinutes)),
            mealRelation: Value(d.meal.token),
            startDate: Value(d.start),
            endDate: Value(d.end),
          ),
          spec: d.spec,
        );
        await _guarded(
          () => scheduleDoseReminders(
            repo: repo,
            notifier: notifier,
            medicineId: id,
            name: d.name,
            dosageLabel: d.dosageLabel,
            mealHint: d.meal.label,
          ),
        );
        return SavedItem(
          kind: d.kind,
          id: id,
          title: d.name,
          route: AppModule.medicine.route,
        );

      case HabitLogDraft d:
        await _ref.read(habitRepositoryProvider).addToDay(d.habitId, d.amount);
        return SavedItem(
          kind: d.kind,
          id: d.habitId,
          title: d.habitName,
          route: AppModule.habits.route,
        );

      case FocusDraft d:
        final timer = _ref.read(focusTimerProvider.notifier);
        if (_ref.read(focusTimerProvider).phase != TimerPhase.idle) {
          throw const AiException('A focus session is already running.');
        }
        timer
          ..setMode(FocusMode.custom)
          ..setCustomMinutes(d.minutes)
          ..linkTask(null);
        await timer.start();
        return SavedItem(
          kind: d.kind,
          title: d.title,
          route: AppModule.focus.route,
        );
    }
  }

  /// Reminder scheduling depends on OS permissions that can be denied or
  /// revoked; a failure there must never lose the row that was just written.
  Future<void> _guarded(Future<void> Function() schedule) async {
    try {
      await schedule();
    } on Exception catch (e) {
      debugPrint('Could not schedule a reminder: $e');
    }
  }
}
