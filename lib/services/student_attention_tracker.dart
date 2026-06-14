import 'dart:async';

import 'package:flutter/widgets.dart';

import '../database/database_helper.dart';

class StudentAttentionTracker with WidgetsBindingObserver {
  StudentAttentionTracker({
    required this.currentPageNotifier,
    DatabaseHelper? database,
    DateTime Function()? now,
  }) : _database = database ?? DatabaseHelper.instance,
       _now = now ?? DateTime.now;

  final ValueNotifier<int> currentPageNotifier;
  final DatabaseHelper _database;
  final DateTime Function() _now;
  final List<Map<String, dynamic>> _history = [];

  String? _sessionId;
  DateTime? _sessionStartedAt;
  DateTime? _currentPageEnteredAt;
  DateTime? _backgroundedAt;
  int? _currentPage;
  String _appLifecycle = 'foreground';

  Future<void> start(String sessionId) async {
    await stop();
    final now = _now().toUtc();
    _sessionId = sessionId;
    _sessionStartedAt = now;
    _currentPage = currentPageNotifier.value;
    _currentPageEnteredAt = now;
    _appLifecycle = 'foreground';
    _backgroundedAt = null;
    _history.clear();
    currentPageNotifier.addListener(_handlePageChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _handlePageChanged() {
    final nextPage = currentPageNotifier.value;
    if (_sessionId == null || nextPage == _currentPage) return;
    final now = _now().toUtc();
    unawaited(_closeCurrentPage(now));
    _currentPage = nextPage;
    _currentPageEnteredAt = now;
  }

  Future<void> _closeCurrentPage(DateTime leftAt) async {
    final sessionId = _sessionId;
    final page = _currentPage;
    final enteredAt = _currentPageEnteredAt;
    if (sessionId == null || page == null || enteredAt == null) return;

    final event = {
      'page': page,
      'enteredAt': enteredAt.toIso8601String(),
      'leftAt': leftAt.toIso8601String(),
      'durationSeconds': leftAt.difference(enteredAt).inSeconds,
    };
    _history.add(event);
    if (_history.length > 20) _history.removeAt(0);
    await _database.insertStudentPageEvent(
      sessionId: sessionId,
      pageNumber: page,
      enteredAt: enteredAt,
      leftAt: leftAt,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = _now().toUtc();
    if (state == AppLifecycleState.resumed) {
      _appLifecycle = 'foreground';
      _backgroundedAt = null;
    } else {
      _appLifecycle = 'background';
      _backgroundedAt ??= now;
    }
  }

  Map<String, dynamic> snapshot() {
    final now = _now().toUtc();
    final enteredAt = _currentPageEnteredAt ?? now;
    return {
      'currentPage': _currentPage ?? currentPageNotifier.value,
      'currentPageEnteredAt': enteredAt.toIso8601String(),
      'currentPageDurationSeconds': now.difference(enteredAt).inSeconds,
      'pageHistory': List<Map<String, dynamic>>.unmodifiable(_history),
      'appLifecycle': _appLifecycle,
      'backgroundedAt': _backgroundedAt?.toIso8601String(),
      'sessionStartedAt': _sessionStartedAt?.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> get history =>
      List<Map<String, dynamic>>.unmodifiable(_history);

  Future<void> stop() async {
    if (_sessionId == null) return;
    currentPageNotifier.removeListener(_handlePageChanged);
    WidgetsBinding.instance.removeObserver(this);
    await _closeCurrentPage(_now().toUtc());
    _sessionId = null;
    _sessionStartedAt = null;
    _currentPageEnteredAt = null;
    _backgroundedAt = null;
    _currentPage = null;
    _history.clear();
  }
}
