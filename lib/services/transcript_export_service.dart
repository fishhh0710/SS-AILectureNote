import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';
import '../database/models.dart';

/// Handles the 10-second interval JSON export of live transcript chunks.
///
/// Every 10 seconds it:
///   1. Captures only the NEW delta text since the last export (may be empty).
///   2. Always writes a numbered segment file: seg_001.json, seg_002.json …
///   3. Updates the 'recording' DB item with the full running transcript.
class TranscriptExportService {
  /// DB parentId for this recording session (e.g. the course item's id).
  final int courseItemParentId;

  /// Human-readable session label, used as the sub-folder name.
  /// e.g. "lecture_20260527_143000"
  final String sessionName;

  final void Function(Map<String, dynamic> segment)? onSegmentExported;

  TranscriptExportService({
    required this.courseItemParentId,
    required this.sessionName,
    this.onSegmentExported,
  });

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The text that was already exported at the previous tick.
  String _lastExportedText = '';

  /// Latest full transcript, updated on every speech-service callback.
  String _currentFullTranscript = '';

  /// Auto-incrementing counter for file naming (1-based).
  int _segmentIndex = 0;

  /// The directory under which seg_NNN.json files are written.
  Directory? _sessionDir;

  /// DB row id of the 'recording' item created when the session starts.
  int? _recordingItemId;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Public path of the session directory (available after [start] completes).
  String get sessionDirPath => _sessionDir?.path ?? '';

  /// Call once when the user presses Start Recording.
  /// Creates the session directory and the DB recording row.
  Future<void> start() async {
    await _ensureSessionDir();
    await _createRecordingItem();
  }

  /// Feed the latest full transcript on every speech-service `onUpdate`.
  void tick(String fullTranscript) {
    _currentFullTranscript = fullTranscript;
  }

  /// Called every 10 seconds by `Timer.periodic` in lecture_view.
  /// Always writes a JSON file — even when no new speech was detected.
  Future<void> exportSegment() async {
    if (_sessionDir == null) return;

    _segmentIndex++;

    final now = DateTime.now().toUtc();
    final fullText = _currentFullTranscript;

    // --- Compute delta text since last export ---
    String deltaText;
    if (fullText.length > _lastExportedText.length &&
        fullText.startsWith(_lastExportedText)) {
      // Normal growth: only the newly added portion
      deltaText = fullText.substring(_lastExportedText.length).trimLeft();
    } else if (fullText == _lastExportedText) {
      // No change at all — silence or pause
      deltaText = '';
    } else {
      // Edge case: text was restructured (e.g. service reset)
      deltaText = fullText;
    }

    _lastExportedText = fullText;

    // --- Build JSON payload per schema ---
    final payload = {
      'timestamp': now.toIso8601String(),
      'duration_seconds': 10,
      'segment_index': _segmentIndex,
      'text': deltaText.trim(),
      'is_empty': deltaText.trim().isEmpty,
    };

    // --- Write seg_NNN.json (always, even when empty) ---
    final fileName = 'seg_${_segmentIndex.toString().padLeft(3, '0')}.json';
    final file = File('${_sessionDir!.path}/$fileName');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    debugPrint(
      '[TranscriptExportService] Wrote $fileName '
      '(is_empty=${payload['is_empty']})',
    );

    // --- Update DB with latest full transcript ---
    await _updateRecordingTranscript(fullText);

    // Notify listeners about the exported segment
    onSegmentExported?.call(payload);
  }

  /// Call when the user presses Stop Recording.
  /// Flushes one final segment and cancels nothing (timer is owned by caller).
  Future<void> stop(String finalTranscript) async {
    _currentFullTranscript = finalTranscript;
    await exportSegment(); // Flush remaining delta (may be empty — still saved)
    await _updateRecordingTranscript(finalTranscript);
    debugPrint(
      '[TranscriptExportService] Session ended. '
      'Total segments: $_segmentIndex. Dir: ${_sessionDir?.path}',
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _ensureSessionDir() async {
    final base = await getApplicationDocumentsDirectory();
    _sessionDir = Directory('${base.path}/transcripts/$sessionName');
    if (!await _sessionDir!.exists()) {
      await _sessionDir!.create(recursive: true);
    }
    debugPrint('[TranscriptExportService] Session dir: ${_sessionDir!.path}');
  }

  Future<void> _createRecordingItem() async {
    final now = DateTime.now().toIso8601String();
    final node = AppNode(
      parentId: courseItemParentId,
      type: 'recording',
      name: '$sessionName.json',
      content: '', // Updated incrementally via _updateRecordingTranscript
      filePath: _sessionDir!.path,
      createdAt: now,
    );
    _recordingItemId = await DatabaseHelper.instance.insertItem(node);
    debugPrint(
      '[TranscriptExportService] Created DB recording item id=$_recordingItemId',
    );
  }

  Future<void> _updateRecordingTranscript(String fullText) async {
    if (_recordingItemId == null) return;
    final existing = await DatabaseHelper.instance.getNodeById(
      _recordingItemId!,
    );
    if (existing == null) return;

    final updated = AppNode(
      id: existing.id,
      parentId: existing.parentId,
      type: existing.type,
      name: existing.name,
      content: fullText,
      filePath: existing.filePath,
      createdAt: existing.createdAt,
    );
    await DatabaseHelper.instance.updateItem(updated);
  }
}
