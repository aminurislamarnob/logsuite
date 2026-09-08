import 'package:flutter_test/flutter_test.dart';
import 'package:mysuite/core/ai/ai_response_parser.dart';
import 'package:mysuite/core/ai/ai_client.dart';
import 'package:mysuite/core/ai/ai_action.dart';

void main() {
  test('Parses Set Budget', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "set_budget", "category": "Groceries", "amount": 500}],
      "reply": "Budget set."
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'SetBudgetAction');
  });
  test('Parses Add Loan', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "add_loan", "amount": 100, "person": "John", "loan_direction": 1}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'AddLoanAction');
  });
  test('Parses Add Bill', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "add_bill", "title": "Netflix", "amount": 15}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'AddBillAction');
  });
  test('Parses Create Account', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "create_account", "title": "Cash"}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'CreateAccountAction');
  });
  test('Parses Create Category', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "create_category", "title": "Ent"}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'CreateCategoryAction');
  });
  test('Parses Log Symptom', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "log_symptom", "symptom": "Headache", "severity": 4}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'LogSymptomAction');
  });
  test('Parses Add Person', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "add_person", "person": "Alice"}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'AddPersonAction');
  });
  test('Parses Create Habit', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "create_habit", "title": "Read"}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'CreateHabitAction');
  });
  test('Parses Create Project', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "create_project", "title": "Reno"}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'CreateProjectAction');
  });
  test('Parses Create Folder', () {
    final res = AiResponseParser.parse('''{
      "actions": [{"kind": "create_folder", "title": "Work"}],
      "reply": ""
    }''', source: const OfflineSource());
    expect(res.actions.first.runtimeType.toString(), 'CreateFolderAction');
  });
}
