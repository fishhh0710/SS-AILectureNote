import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

import '../services/annotation_manager.dart';
import '../services/firebase_function_client.dart';
import '../viewmodels/lecture_notes_view_model.dart';
import '../viewmodels/slides_view_model.dart';

class _QueuedTranscriptChunk {
  const _QueuedTranscriptChunk({
    required this.latestSegment,
    required this.recentSegments,
  });

  final String latestSegment;
  final List<String> recentSegments;
}

class _QueuedRealtimeAction {
  const _QueuedRealtimeAction({
    required this.decoded,
    required this.pageNumber,
  });

  final Map<String, dynamic> decoded;
  final int pageNumber;
}

class RealtimeAgentCoordinator {
  RealtimeAgentCoordinator({
    required this.storageId,
    required this.courseId,
    required this.slidesViewModel,
    required this.notesViewModel,
    required this.segmentStream,
    required this.getAnnotationManager,
    required this.getPdfDocument,
    required this.sessionId,
    required this.getStudentState,
    this.notificationToken,
    FirebaseFunctionClient? functionClient,
  }) : _functionClient = functionClient ?? FirebaseFunctionClient() {
    _subscribe();
  }

  final String storageId;
  final String courseId;
  final SlidesViewModel slidesViewModel;
  final LectureNotesViewModel notesViewModel;
  final Stream<Map<String, dynamic>> segmentStream;
  final PageAnnotationManager? Function() getAnnotationManager;
  final PdfDocument? Function() getPdfDocument;
  final String sessionId;
  final Map<String, dynamic> Function() getStudentState;
  final String? notificationToken;
  final FirebaseFunctionClient _functionClient;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<_QueuedTranscriptChunk> _pendingChunks = [];
  final List<_QueuedRealtimeAction> _pendingActions = [];
  final List<String> _recentSegments = [];
  int? _lastTeacherPage;
  bool _isProcessing = false;
  bool _isApplyingAction = false;
  bool _isDisposed = false;

  void _subscribe() {
    _subscription = segmentStream.listen((event) {
      final text = event['text'] as String? ?? '';
      final isEmpty = event['is_empty'] as bool? ?? true;
      final latestSegment = text.trim();
      if (isEmpty || latestSegment.isEmpty) return;

      _pendingChunks.add(
        _QueuedTranscriptChunk(
          latestSegment: latestSegment,
          recentSegments: List.unmodifiable(_recentSegments.takeLast(9)),
        ),
      );
      _recentSegments.add(latestSegment);
      if (_recentSegments.length > 10) {
        _recentSegments.removeRange(0, _recentSegments.length - 10);
      }
      unawaited(_drainQueue());
    });
  }

  Future<void> _drainQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (!_isDisposed && _pendingChunks.isNotEmpty) {
        final chunk = _pendingChunks.removeAt(0);
        await _processTranscriptChunk(chunk);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processTranscriptChunk(_QueuedTranscriptChunk chunk) async {
    try {
      final doc = getPdfDocument();
      final annotationManager = getAnnotationManager();
      if (doc == null || annotationManager == null) {
        // ignore: avoid_print
        print('DEBUG [Agent]: PDF or annotation manager is not ready.');
        return;
      }

      final decoded = FirebaseFunctionClient.unwrapPayload(
        await _functionClient.postJson(
          functionName: 'realtimeAgent',
          body: {
            'lastTeacherPage': _lastTeacherPage,
            'pageSummaries': notesViewModel.notes
                .map((note) => note.toJson())
                .toList(),
            'recentSegments': chunk.recentSegments,
            'latestSegment': chunk.latestSegment,
            'sessionId': sessionId,
            'courseId': courseId,
            'lectureId': storageId,
            'studentState': getStudentState(),
            'notificationToken': notificationToken,
          },
        ),
      );

      final pageNumber = _positiveInt(decoded['page_number']);
      if (pageNumber == null || pageNumber > doc.pages.length) return;
      _lastTeacherPage = pageNumber;
      await _handleAttention(decoded['attention'], pageNumber);
      _pendingActions.add(
        _QueuedRealtimeAction(decoded: decoded, pageNumber: pageNumber),
      );
      unawaited(_drainActions());
    } catch (error) {
      // ignore: avoid_print
      print('DEBUG [Agent]: Realtime processing failed: $error');
    }
  }

  Future<void> _drainActions() async {
    if (_isApplyingAction) return;
    _isApplyingAction = true;

    try {
      while (!_isDisposed && _pendingActions.isNotEmpty) {
        final action = _pendingActions.removeAt(0);
        await _applyRealtimeAction(action.decoded, action.pageNumber);
      }
    } finally {
      _isApplyingAction = false;
    }
  }

  Future<void> _applyRealtimeAction(
    Map<String, dynamic> decoded,
    int pageNumber,
  ) async {
    try {
      final doc = getPdfDocument();
      final annotationManager = getAnnotationManager();
      if (doc == null || annotationManager == null) {
        // ignore: avoid_print
        print('DEBUG [Agent]: PDF or annotation manager is not ready.');
        return;
      }
      if (pageNumber > doc.pages.length) return;

      final action = decoded['update_note_at'] as String? ?? 'none';
      if (action == 'summary') {
        final updated = await notesViewModel.appendRealtimeUpdate(
          storageId: storageId,
          pageNumber: pageNumber,
          newPoints: _stringList(decoded['new_points']),
          questions: _stringList(decoded['questions']),
        );
        if (!updated) {
          // ignore: avoid_print
          print(
            'DEBUG [Agent]: Summary page $pageNumber does not exist or has no new content.',
          );
        }
        return;
      }

      if (action == 'slides') {
        final targets = _mapList(decoded['targets']);
        if (targets.isEmpty) return;
        await slidesViewModel.processPageWithTargets(
          page: doc.pages[pageNumber - 1],
          pageIndex: pageNumber,
          targets: targets,
          annotationManager: annotationManager,
        );
      }
    } catch (error) {
      // ignore: avoid_print
      print('DEBUG [Agent]: Realtime action failed: $error');
    }
  }

  Future<void> _handleAttention(Object? value, int teacherPage) async {
    if (value is! Map) return;
    final attention = Map<String, dynamic>.from(value);
    if (attention['checked'] != true || attention['status'] != 'distracted') {
      return;
    }
    // Notification delivery is owned by the backend so the Firestore cooldown
    // remains authoritative. Foreground display is handled by FCM onMessage.
    if (attention['notification_sent'] != true) {
      // ignore: avoid_print
      print(
        'DEBUG [Attention]: Notification skipped by backend: '
        '${attention['notification_reason'] ?? 'unknown'}',
      );
    }
  }

  int? _positiveInt(Object? value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    return null;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void dispose() {
    _isDisposed = true;
    _pendingChunks.clear();
    _pendingActions.clear();
    _recentSegments.clear();
    unawaited(_subscription?.cancel());
    _functionClient.dispose();
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList();
    if (values.length <= count) return values;
    return values.skip(values.length - count);
  }
}
