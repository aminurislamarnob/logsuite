import 'ai_action.dart';

/// One tool as a future MCP server would expose it: a name, a description
/// and a strict JSON-schema object for its arguments.
class AiToolSpec {
  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  const AiToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}

/// A field of the action object and the kinds that use it.
class _Field {
  final Map<String, Object?> schema;
  final Set<AiActionKind> kinds;

  const _Field(this.schema, this.kinds);
}

/// The single source of truth for what the model may return.
///
/// Every provider gets the same [root] schema: an `actions` array whose items
/// are one flat object with a `kind` discriminator and every field nullable.
/// A flat object rather than a `anyOf` per kind because the strict modes of
/// all four providers accept it, whereas union support differs between them.
///
/// The same field table also yields [tools], one strict spec per kind with
/// only that kind's fields. Nothing reads it yet; it exists so that an MCP
/// server, if one is ever added, exposes exactly what the prompt describes
/// rather than a second hand-maintained list.
class AiCommandSchema {
  const AiCommandSchema._();

  static const _expense = {AiActionKind.addExpense};
  static const _task = {AiActionKind.addTask};
  static const _medicine = {AiActionKind.addMedicine};
  static const _habit = {AiActionKind.logHabit};
  static const _focus = {AiActionKind.startFocus};
  static const _budget = {AiActionKind.setBudget};
  static const _loan = {AiActionKind.addLoan};
  static const _bill = {AiActionKind.addBill};
  static const _account = {AiActionKind.createAccount};
  static const _category = {AiActionKind.createCategory};
  static const _symptom = {AiActionKind.logSymptom};
  static const _person = {AiActionKind.addPerson};
  static const _habitCreate = {AiActionKind.createHabit};
  static const _project = {AiActionKind.createProject};
  static const _folder = {AiActionKind.createFolder};

  static const _fields = <String, _Field>{
    'title': _Field(
      {
        'type': ['string', 'null'],
        'description':
            'The task title, note title, expense description, medicine '
            'name, account name, category name, bill title, symptom, person name, habit name, project name, or folder name.',
      },
      {
        AiActionKind.addExpense,
        AiActionKind.addTask,
        AiActionKind.addNote,
        AiActionKind.addMedicine,
        AiActionKind.addBill,
        AiActionKind.createAccount,
        AiActionKind.createCategory,
        AiActionKind.logSymptom,
        AiActionKind.addPerson,
        AiActionKind.createHabit,
        AiActionKind.createProject,
        AiActionKind.createFolder,
      },
    ),
    'amount': _Field(
      {
        'type': ['number', 'null'],
        'description': 'Money amount.',
      },
      {
        AiActionKind.addExpense,
        AiActionKind.setBudget,
        AiActionKind.addLoan,
        AiActionKind.addBill,
      },
    ),
    'kind_detail': _Field({
      'type': ['string', 'null'],
      'description': 'For add_expense: "expense" (money out) or "income".',
    }, _expense),
    'category': _Field(
      {
        'type': ['string', 'null'],
        'description':
            'One of the listed expense categories, exactly as written, or '
            'null when none fits.',
      },
      {AiActionKind.addExpense, AiActionKind.setBudget, AiActionKind.addBill},
    ),
    'account': _Field(
      {
        'type': ['string', 'null'],
        'description': 'One of the listed accounts, exactly as written, or null.',
      },
      {AiActionKind.addExpense, AiActionKind.addLoan, AiActionKind.addBill},
    ),
    'person': _Field(
      {
        'type': ['string', 'null'],
        'description':
            'One of the listed people, exactly as written: who the expense '
            'was for, who takes the medicine, or who the loan is with.',
      },
      {AiActionKind.addExpense, AiActionKind.addMedicine, AiActionKind.addLoan, AiActionKind.logSymptom},
    ),
    'date': _Field(
      {
        'type': ['string', 'null'],
        'description': 'Calendar date as yyyy-MM-dd, or null for today.',
      },
      {AiActionKind.addExpense, AiActionKind.addTask},
    ),
    'time': _Field({
      'type': ['string', 'null'],
      'description': 'Time of day as 24-hour HH:mm, or null.',
    }, _task),
    'reminder': _Field(
      {
        'type': ['string', 'null'],
        'description':
            'When to notify, as yyyy-MM-ddTHH:mm local time. Set whenever '
            'the user says remind me.',
      },
      {AiActionKind.addTask, AiActionKind.addNote},
    ),
    'priority': _Field({
      'type': ['integer', 'null'],
      'description': 'Task priority 1 (highest) to 4 (none).',
    }, _task),
    'recurrence': _Field({
      'type': ['string', 'null'],
      'description':
          'One of daily, weekdays, weekly, biweekly, monthly, yearly, or '
          'every:N for every N days.',
    }, _task),
    'tags': _Field(
      {
        'type': ['array', 'null'],
        'items': {'type': 'string'},
        'description': 'Tags the user named explicitly.',
      },
      {AiActionKind.addTask, AiActionKind.addNote},
    ),
    'note_body': _Field(
      {
        'type': ['string', 'null'],
        'description': 'The body text of a note, or extra notes for medicine.',
      },
      {AiActionKind.addNote, AiActionKind.addMedicine, AiActionKind.logSymptom},
    ),
    'medicine_form': _Field({
      'type': ['string', 'null'],
      'description': 'tablet, capsule, syrup, injection, drops or inhaler.',
    }, _medicine),
    'dosage': _Field({
      'type': ['number', 'null'],
      'description': 'Units per dose, e.g. 1 for one tablet, 5 for 5 ml.',
    }, _medicine),
    'dosage_unit': _Field({
      'type': ['string', 'null'],
      'description': 'The unit of one dose: tablet, ml, mg, drops.',
    }, _medicine),
    'times_per_day': _Field({
      'type': ['integer', 'null'],
      'description':
          'How many doses a day. Leave dose_times null unless '
          'the user gave clock times.',
    }, _medicine),
    'dose_times': _Field({
      'type': ['array', 'null'],
      'items': {'type': 'string'},
      'description': 'Clock times as HH:mm, only when the user said them.',
    }, _medicine),
    'days': _Field({
      'type': ['integer', 'null'],
      'description': 'Length of the course in days.',
    }, _medicine),
    'meal_relation': _Field({
      'type': ['string', 'null'],
      'description': 'none, before, after or with (food).',
    }, _medicine),
    'habit': _Field({
      'type': ['string', 'null'],
      'description': 'One of the listed habits, exactly as written.',
    }, _habit),
    'habit_amount': _Field({
      'type': ['number', 'null'],
      'description': 'How much to log, in the habit unit. Default 1.',
    }, _habit),
    'loan_direction': _Field({
      'type': ['integer', 'null'],
      'description': '0 for lend, 1 for borrow.',
    }, _loan),
    'bill_period': _Field({
      'type': ['string', 'null'],
      'description': 'e.g., daily, weekly, monthly, yearly.',
    }, _bill),
    'bill_interval': _Field({
      'type': ['integer', 'null'],
      'description': 'The interval multiplier for the bill period, e.g., 1.',
    }, _bill),
    'is_income': _Field({
      'type': ['boolean', 'null'],
      'description': 'True if creating an income category, false otherwise.',
    }, _category),
    'severity': _Field({
      'type': ['integer', 'null'],
      'description': 'Symptom severity from 1 (mild) to 5 (severe). Default 3.',
    }, _symptom),
    'relation': _Field({
      'type': ['string', 'null'],
      'description': 'Relation of the person, e.g., Family, Friend, Doctor.',
    }, _person),
    'focus_minutes': _Field({
      'type': ['integer', 'null'],
      'description': 'Length of the focus session in minutes. Default 25.',
    }, _focus),
  };

  /// The flat action object every provider receives.
  static Map<String, Object?> get action {
    final properties = <String, Object?>{
      'kind': {
        'type': 'string',
        'enum': [for (final k in AiActionKind.values) k.wire],
        'description': 'Which entry to create.',
      },
      for (final e in _fields.entries) e.key: e.value.schema,
    };
    return {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
      'additionalProperties': false,
    };
  }

  static Map<String, Object?> get root => {
    'type': 'object',
    'properties': {
      'actions': {
        'type': 'array',
        'items': action,
        'description': 'One entry per thing the user asked to add.',
      },
      'reply': {
        'type': 'string',
        'description':
            'At most one short sentence for the user. Empty when nothing '
            'needs saying.',
      },
      'needs_clarification': {
        'type': 'boolean',
        'description':
            'True only when a required detail such as an amount or a name '
            'is missing and cannot be guessed.',
      },
    },
    'required': ['actions', 'reply', 'needs_clarification'],
    'additionalProperties': false,
  };

  /// One strict tool per kind, with only the fields that kind uses.
  static List<AiToolSpec> get tools => [
    for (final kind in AiActionKind.values)
      AiToolSpec(
        name: kind.wire,
        description: _descriptions[kind]!,
        inputSchema: _toolSchema(kind),
      ),
  ];

  static Map<String, Object?> _toolSchema(AiActionKind kind) {
    final properties = <String, Object?>{
      for (final e in _fields.entries)
        if (e.value.kinds.contains(kind)) e.key: e.value.schema,
    };
    return {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
      'additionalProperties': false,
    };
  }

  static const _descriptions = <AiActionKind, String>{
    AiActionKind.addExpense:
        'Record money spent or received against an account and category.',
    AiActionKind.addTask:
        'Create a to-do with an optional due date, time, reminder and repeat.',
    AiActionKind.addNote: 'Create a note with a title and body text.',
    AiActionKind.addMedicine:
        'Add a medicine course with doses per day and a length in days.',
    AiActionKind.logHabit: 'Log progress on one of the existing habits today.',
    AiActionKind.startFocus: 'Start a focus timer for a number of minutes.',
    AiActionKind.setBudget: 'Set or update a monthly budget for a category. Use this even when the user says they added a budget.',
    AiActionKind.addLoan: 'Track money you lend to or borrow from someone.',
    AiActionKind.addBill: 'Add a recurring expense or subscription bill.',
    AiActionKind.createAccount: 'Create a new financial account.',
    AiActionKind.createCategory: 'Create a new expense or income category.',
    AiActionKind.logSymptom: 'Log a symptom you are experiencing right now.',
    AiActionKind.addPerson: 'Add a new person to your contacts or household.',
    AiActionKind.createHabit: 'Create a new habit to track.',
    AiActionKind.createProject: 'Create a new project for tasks.',
    AiActionKind.createFolder: 'Create a new folder for notes.',
  };

  /// The same schema in the OpenAPI dialect Gemini's `responseSchema`
  /// accepts: no `additionalProperties`, and `["x", "null"]` types become
  /// `type: x` with `nullable: true`.
  static Map<String, Object?> openApiSubset(Map<String, Object?> schema) {
    final out = <String, Object?>{};
    schema.forEach((key, value) {
      if (key == 'additionalProperties') return;
      if (key == 'type' && value is List) {
        final types = value.whereType<String>().where((t) => t != 'null');
        out['type'] = types.isEmpty ? 'string' : types.first;
        if (value.contains('null')) out['nullable'] = true;
        return;
      }
      if (value is Map<String, Object?>) {
        out[key] = openApiSubset(value);
      } else if (value is Map) {
        out[key] = openApiSubset(Map<String, Object?>.from(value));
      } else if (value is List) {
        out[key] = [
          for (final v in value)
            v is Map ? openApiSubset(Map<String, Object?>.from(v)) : v,
        ];
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}
