import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:budgetwise_server/src/auth/tokens.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/http/errors.dart';
import 'package:budgetwise_server/src/http/middleware.dart';
import 'package:budgetwise_server/src/repositories/budget_repository.dart';
import 'package:budgetwise_server/src/repositories/expense_repository.dart';
import 'package:budgetwise_server/src/repositories/goal_repository.dart';
import 'package:budgetwise_server/src/repositories/investing_repository.dart';
import 'package:budgetwise_server/src/routes/auth_routes.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Everything behind a session.
///
/// Each handler starts by taking the principal from the request context, and
/// builds its repositories from that owner id. There is no path by which a
/// handler can operate on an owner supplied by the caller — that is the whole
/// design, and it is what stands in for row-level security.
class ApiRoutes {
  ApiRoutes({required this.mongo, required this.tokens});

  final Mongo mongo;
  final TokenService tokens;

  Router get router => Router()
    ..get('/me', _me)
    ..patch('/me', _updateMe)
    ..delete('/me', _deleteAccount)
    ..get('/budgets', _listBudgets)
    ..post('/budgets', _createBudget)
    ..get('/budgets/current', _currentBudget)
    ..get('/summaries', _listSummaries)
    ..get('/summaries/<period>', _summaryForPeriod)
    ..get('/budgets/<budgetId>/categories', _categories)
    ..patch('/categories/<categoryId>', _updateCategory)
    ..get('/budgets/<budgetId>/expenses', _listExpenses)
    ..post('/expenses', _createExpense)
    ..patch('/expenses/<expenseId>', _updateExpense)
    ..delete('/expenses/<expenseId>', _deleteExpense)
    ..post('/budgets/<budgetId>/confirm-savings', _confirmSavings)
    ..get('/goals', _listGoals)
    ..post('/goals', _createGoal)
    ..post('/goals/<goalId>/contribute', _contribute)
    ..delete('/goals/<goalId>', _deleteGoal)
    ..get('/investing/status', _investingStatus)
    ..post('/investing', _recordInvestment);

  BudgetRepository _budgets(Request r) =>
      BudgetRepository(mongo, principalOf(r).ownerId);
  ExpenseRepository _expenses(Request r) =>
      ExpenseRepository(mongo, principalOf(r).ownerId);
  GoalRepository _goals(Request r) =>
      GoalRepository(mongo, principalOf(r).ownerId);
  InvestingRepository _investing(Request r) =>
      InvestingRepository(mongo, principalOf(r).ownerId);

  // --- account -------------------------------------------------------------

  Future<Response> _me(Request request) async {
    final user = await mongo
        .collection(Col.users)
        .findOne(where.id(principalOf(request).ownerId));
    if (user == null) throw const ApiException.notFound('Account not found.');
    return jsonResponse(publicUser(user));
  }

  Future<Response> _updateMe(Request request) async {
    final body = await readJson(request);
    final changes = <String, dynamic>{
      if (body.containsKey('onboardingCompleted') &&
          body['onboardingCompleted'] == true)
        'onboardingCompletedAt': DateTime.now().toUtc(),
      if (body['displayName'] is String) 'displayName': body['displayName'],
    };
    if (changes.isEmpty) {
      throw const ApiException.badRequest('Nothing to update.');
    }

    final ownerId = principalOf(request).ownerId;
    await mongo.collection(Col.users).updateOne(where.id(ownerId), {
      r'$set': changes,
    });
    final user = await mongo.collection(Col.users).findOne(where.id(ownerId));
    return jsonResponse(publicUser(user!));
  }

  /// Deletes the account and everything in it.
  ///
  /// Required by both app stores. A relational schema did this with `on delete cascade`;
  /// here it is an explicit sweep of every collection — see
  /// [Mongo.deleteEverythingOwnedBy].
  Future<Response> _deleteAccount(Request request) async {
    final ownerId = principalOf(request).ownerId;
    await tokens.revokeAllFor(ownerId);
    await mongo.deleteEverythingOwnedBy(ownerId);
    return Response(204);
  }

  // --- budgets -------------------------------------------------------------

  Future<Response> _listBudgets(Request request) async =>
      jsonResponse(_serialiseAll(await _budgets(request).allBudgets()));

  Future<Response> _currentBudget(Request request) async {
    final budget = await _budgets(request).budgetForPeriod(Period.current());
    return jsonResponse(budget == null ? null : _serialise(budget));
  }

  Future<Response> _createBudget(Request request) async {
    final body = await readJson(request);

    final period = Period.parse(_requireString(body, 'period'));
    final income = Money(_requireInt(body, 'incomeMinor'));
    final savingsTarget = Money(_requireInt(body, 'savingsTargetMinor'));
    final categories = (body['categories'] as List?)
        ?.cast<Map<String, dynamic>>();
    if (categories == null || categories.isEmpty) {
      throw const ApiException.badRequest(
        'A month needs at least one category.',
      );
    }

    final budget = await _budgets(request).createMonth(
      period: period,
      income: income,
      savingsMode: SavingsMode.fromDb(
        body['savingsMode'] as String? ?? 'percent',
      ),
      savingsTarget: savingsTarget,
      savingsPercent: (body['savingsPercent'] as num?)?.toDouble(),
      investmentTarget: body['investmentTargetMinor'] == null
          ? null
          : Money((body['investmentTargetMinor'] as num).toInt()),
      carriedFrom: body['carriedFromPeriod'] == null
          ? null
          : Period.parse(body['carriedFromPeriod'] as String),
      categories: categories,
    );

    return jsonResponse(_serialise(budget), status: 201);
  }

  Future<Response> _listSummaries(Request request) async =>
      jsonResponse(await _budgets(request).allSummaries());

  Future<Response> _summaryForPeriod(Request request, String period) async =>
      jsonResponse(
        await _budgets(request).summaryForPeriod(Period.parse(period)),
      );

  Future<Response> _categories(Request request, String budgetId) async =>
      jsonResponse(await _budgets(request).categorySpend(_objectId(budgetId)));

  Future<Response> _updateCategory(Request request, String categoryId) async {
    final body = await readJson(request);
    final updated = await _budgets(request).updateCategoryAllocation(
      categoryId: _objectId(categoryId),
      allocated: Money(_requireInt(body, 'allocatedMinor')),
      percent: (body['allocatedPercent'] as num?)?.toDouble() ?? 0,
    );
    if (updated == null) throw const ApiException.notFound();
    return jsonResponse(_serialise(updated));
  }

  Future<Response> _confirmSavings(Request request, String budgetId) async {
    final body = await readJson(request);
    await _budgets(request).confirmSavings(
      budgetId: _objectId(budgetId),
      amount: Money(_requireInt(body, 'amountMinor')),
      destination: body['destination'] as String? ?? 'bank',
    );
    return Response(204);
  }

  // --- expenses ------------------------------------------------------------

  Future<Response> _listExpenses(Request request, String budgetId) async =>
      jsonResponse(
        _serialiseAll(await _expenses(request).forBudget(_objectId(budgetId))),
      );

  Future<Response> _createExpense(Request request) async {
    final body = await readJson(request);
    final expense = await _expenses(request).add(
      budgetId: _objectId(_requireString(body, 'budgetId')),
      categoryId: _objectId(_requireString(body, 'categoryId')),
      amount: Money(_requireInt(body, 'amountMinor')),
      spentOn: DateTime.parse(_requireString(body, 'spentOn')),
      paymentMethod: body['paymentMethod'] as String? ?? 'upi',
      note: body['note'] as String?,
    );
    return jsonResponse(_serialise(expense), status: 201);
  }

  Future<Response> _updateExpense(Request request, String expenseId) async {
    final body = await readJson(request);
    final expense = await _expenses(request).update(
      id: _objectId(expenseId),
      categoryId: _objectId(_requireString(body, 'categoryId')),
      amount: Money(_requireInt(body, 'amountMinor')),
      spentOn: DateTime.parse(_requireString(body, 'spentOn')),
      paymentMethod: body['paymentMethod'] as String? ?? 'upi',
      note: body['note'] as String?,
    );
    if (expense == null) throw const ApiException.notFound();
    return jsonResponse(_serialise(expense));
  }

  Future<Response> _deleteExpense(Request request, String expenseId) async {
    final deleted = await _expenses(request).delete(_objectId(expenseId));
    if (!deleted) throw const ApiException.notFound();
    return Response(204);
  }

  // --- goals ---------------------------------------------------------------

  Future<Response> _listGoals(Request request) async =>
      jsonResponse(_serialiseAll(await _goals(request).all()));

  Future<Response> _createGoal(Request request) async {
    final body = await readJson(request);
    final goal = await _goals(request).create(
      title: _requireString(body, 'title'),
      target: Money(_requireInt(body, 'targetMinor')),
      targetDate: body['targetDate'] == null
          ? null
          : DateTime.parse(body['targetDate'] as String),
      monthlyContribution: body['monthlyContributionMinor'] == null
          ? null
          : Money((body['monthlyContributionMinor'] as num).toInt()),
      icon: body['icon'] as String?,
    );
    return jsonResponse(_serialise(goal), status: 201);
  }

  Future<Response> _contribute(Request request, String goalId) async {
    final body = await readJson(request);
    await _goals(request).contribute(
      goalId: _objectId(goalId),
      amount: Money(_requireInt(body, 'amountMinor')),
      budgetId: body['budgetId'] == null
          ? null
          : _objectId(body['budgetId'] as String),
    );
    return Response(204);
  }

  Future<Response> _deleteGoal(Request request, String goalId) async {
    final deleted = await _goals(request).delete(_objectId(goalId));
    if (!deleted) throw const ApiException.notFound();
    return Response(204);
  }

  // --- investing -----------------------------------------------------------

  Future<Response> _investingStatus(Request request) async =>
      jsonResponse(await _investing(request).claimUnlock());

  Future<Response> _recordInvestment(Request request) async {
    final body = await readJson(request);
    final investment = await _investing(request).recordInvestment(
      budgetId: _objectId(_requireString(body, 'budgetId')),
      amount: Money(_requireInt(body, 'amountMinor')),
      instrument: body['instrument'] as String? ?? 'other',
      note: body['note'] as String?,
    );
    return jsonResponse(_serialise(investment), status: 201);
  }
}

// --- serialisation ---------------------------------------------------------

/// Renders a Mongo document as JSON the client can read.
///
/// ObjectId and DateTime have no JSON representation of their own, so every id
/// becomes its hex string and every instant an ISO-8601 string. Done centrally
/// because a single route that forgets produces a body the client cannot parse
/// and an error that points nowhere near the cause.
Map<String, dynamic> _serialise(Map<String, dynamic> document) {
  final out = <String, dynamic>{};
  for (final entry in document.entries) {
    final key = entry.key == '_id' ? 'id' : entry.key;
    out[key] = _value(entry.value);
  }
  // ownerId is never sent: the client already knows who it is, and echoing it
  // invites code that trusts the body's owner instead of the token's.
  out.remove('ownerId');
  return out;
}

Object? _value(Object? value) => switch (value) {
  final ObjectId id => id.oid,
  final DateTime date => date.toUtc().toIso8601String(),
  final Map<String, dynamic> map => _serialise(map),
  final List<dynamic> list => list.map(_value).toList(),
  _ => value,
};

List<Map<String, dynamic>> _serialiseAll(
  List<Map<String, dynamic>> documents,
) => [for (final document in documents) _serialise(document)];

ObjectId _objectId(String value) {
  try {
    return ObjectId.fromHexString(value);
  } on Object {
    throw const ApiException.notFound();
  }
}

String _requireString(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value is! String || value.isEmpty) {
    throw ApiException.badRequest('$key is required.');
  }
  return value;
}

int _requireInt(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value is! num) throw ApiException.badRequest('$key is required.');
  return value.toInt();
}
