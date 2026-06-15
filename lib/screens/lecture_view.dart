import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/slides_panel.dart';
import '../widgets/transcript_panel.dart';
import '../widgets/summary_panel.dart';
import '../widgets/chatbot_panel.dart';
import '../services/azure_speech_service.dart';
import '../services/auth_service.dart';
import '../services/transcript_export_service.dart';
import '../viewmodels/lecture_notes_view_model.dart';
import '../services/realtime_agent_coordinator.dart';
import '../services/student_attention_tracker.dart';
import '../services/user_identity_service.dart';
import '../services/notification_service.dart';
import '../data/transcript_data.dart';

class LectureView extends StatefulWidget {
  final String courseId;
  final String fileId;

  const LectureView({super.key, required this.courseId, required this.fileId});

  @override
  State<LectureView> createState() => _LectureViewState();
}

class _LectureViewState extends State<LectureView> {
  bool _showSlides = true;
  bool _showTranscript = true;
  bool _showSummary = false;
  bool _showChatbot = false;
  bool _isRecording = false;
  final GlobalKey _panelsAreaKey = GlobalKey();
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  final GlobalKey<SlidesPanelState> _slidesPanelKey =
      GlobalKey<SlidesPanelState>();
  RealtimeAgentCoordinator? _realtimeAgentCoordinator;
  late final StudentAttentionTracker _studentAttentionTracker;
  final UserIdentityService _userIdentityService = UserIdentityService();

  late AzureSpeechService _speechService;
  late AzureAuthService _authService;
  StreamSubscription? _transcriptSubscription;
  StreamSubscription? _statusSubscription;
  late final LectureNotesViewModel _notesViewModel;
  String _liveTranscript = '';
  String _currentLanguage = 'en_US';
  String? _savedStatusText;

  // 10-second export service
  TranscriptExportService? _exportService;
  Timer? _exportTimer;

  bool _isDemoMode = false;
  Timer? _demoTimer;
  int _demoSectionIndex = 0;
  int _demoIncrementIndex = 0;
  List<String> _demoIncrements = [];
  String _demoAccumulatedText = "";
  String _demoCurrentActiveText = "";
  final StreamController<Map<String, dynamic>> _segmentStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  void initState() {
    super.initState();
    _notesViewModel = LectureNotesViewModel()
      ..addListener(_handleNotesStateChanged);
    _studentAttentionTracker = StudentAttentionTracker(
      currentPageNotifier: _currentPageNotifier,
    );

    _speechService = AzureSpeechService();
    _authService = AzureAuthService();

    _transcriptSubscription = _speechService.transcriptStream.listen((text) {
      if (!mounted) return;
      setState(() {
        _liveTranscript = text;
      });
      // Feed the latest transcript to the export service on every update
      _exportService?.tick(text);
    });

    _statusSubscription = _speechService.statusStream.listen((listening) {
      if (!mounted) return;
      setState(() {
        _isRecording = listening;
      });
    });

    _initializeSpeechService();
    unawaited(_notesViewModel.loadSaved(widget.fileId));
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _segmentStreamController.close();
    _realtimeAgentCoordinator?.dispose();
    unawaited(_studentAttentionTracker.stop());
    _currentPageNotifier.dispose();
    _notesViewModel
      ..removeListener(_handleNotesStateChanged)
      ..dispose();
    _exportTimer?.cancel();
    _transcriptSubscription?.cancel();
    _statusSubscription?.cancel();
    _speechService.dispose();
    _authService.dispose();
    super.dispose();
  }

  void _handleNotesStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _initializeSpeechService() async {
    final savedPath = await _speechService.loadSavedTranscript(widget.fileId);
    if (mounted && savedPath != null) {
      setState(() {
        _savedStatusText = 'Saved transcript loaded';
      });
    }
  }

  double _getMinWidth(String id) {
    if (id == 'slides') return 500.0;
    return 330.0;
  }

  void _togglePanel(String id) {
    // hide panel
    if (id == 'slides' && _showSlides) {
      setState(() {
        _showSlides = false;
      });
      return;
    } else if (id == 'transcript' && _showTranscript) {
      setState(() {
        _showTranscript = false;
      });
      return;
    } else if (id == 'summary' && _showSummary) {
      setState(() {
        _showSummary = false;
      });
      return;
    } else if (id == 'chatbot' && _showChatbot) {
      setState(() {
        _showChatbot = false;
      });
      return;
    }

    // Always allow adding the panel, as the UI handles horizontal scrolling
    // when panels exceed the available width.
    setState(() {
      if (id == 'slides') {
        _showSlides = true;
      } else if (id == 'transcript') {
        _showTranscript = true;
      } else if (id == 'summary') {
        _showSummary = true;
      } else {
        _showChatbot = true;
      }
      // Move the newly added panel to the far right of the layout
      _layoutOrder.remove(id);
      _layoutOrder.add(id);
    });
  }

  final List<String> _layoutOrder = [
    "slides",
    "transcript",
    "summary",
    "chatbot",
  ];

  final Map<String, double> _panelWeights = {
    "slides": 50.0,
    "transcript": 25.0,
    "summary": 25.0,
    "chatbot": 25.0,
  };

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      // Get currently visible IDs
      List<String> visibleIds = [];
      for (var id in _layoutOrder) {
        if ((id == 'slides' && _showSlides) ||
            (id == 'transcript' && _showTranscript) ||
            (id == 'summary' && _showSummary) ||
            (id == 'chatbot' && _showChatbot)) {
          visibleIds.add(id);
        }
      }

      String draggedItem = visibleIds[oldIndex];
      String targetItem = visibleIds[newIndex];

      int dragIdxInLayout = _layoutOrder.indexOf(draggedItem);
      _layoutOrder.removeAt(dragIdxInLayout);

      int insertIdxInLayout = _layoutOrder.indexOf(targetItem);
      if (oldIndex < newIndex) {
        _layoutOrder.insert(insertIdxInLayout + 1, draggedItem);
      } else {
        _layoutOrder.insert(insertIdxInLayout, draggedItem);
      }
    });
  }

  Future<void> _handleRecordingToggle() async {
    if (_isRecording) {
      if (_isDemoMode) {
        _stopDemoTyping();
        setState(() {
          _isRecording = false;
        });
      } else {
        await _speechService.stopListening();
      }

      _realtimeAgentCoordinator?.dispose();
      _realtimeAgentCoordinator = null;
      await _studentAttentionTracker.stop();

      _exportTimer?.cancel();
      _exportTimer = null;

      final exportService = _exportService;
      final savedDir = exportService?.sessionDirPath ?? '';
      await exportService?.stop(_liveTranscript);
      _exportService = null;

      if (!mounted) return;

      setState(() {
        _savedStatusText = savedDir.isEmpty
            ? 'Transcript saved locally'
            : 'Transcript saved to: $savedDir';
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _savedStatusText = null;
        });
      });
      return;
    }

    setState(() {
      _savedStatusText = null;
      // Keep the existing transcript so it is not cleared on restart
      _isRecording = true;
    });

    final now = DateTime.now();
    final sessionName =
        'lecture_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final parentId = int.tryParse(widget.fileId) ?? 0;

    final exportService = TranscriptExportService(
      courseItemParentId: parentId,
      sessionName: sessionName,
      onSegmentExported: (segment) {
        _segmentStreamController.add(segment);
      },
    );
    _exportService = exportService;

    try {
      await _userIdentityService.ensureSignedIn();
      await _studentAttentionTracker.start(sessionName);
      final notificationToken = await NotificationService.instance.getToken();
      await exportService.start();

      final state = _slidesPanelKey.currentState;
      if (state != null) {
        _realtimeAgentCoordinator = RealtimeAgentCoordinator(
          storageId: widget.fileId,
          courseId: widget.courseId,
          slidesViewModel: state.viewModel,
          notesViewModel: _notesViewModel,
          segmentStream: _segmentStreamController.stream,
          getAnnotationManager: () =>
              _slidesPanelKey.currentState?.annotationManager,
          getPdfDocument: () => _slidesPanelKey.currentState?.document,
          sessionId: sessionName,
          getStudentState: _studentAttentionTracker.snapshot,
          notificationToken: notificationToken,
        );
      }
    } catch (e) {
      await _studentAttentionTracker.stop();
      _exportService = null;
      if (!mounted) return;
      setState(() {
        _isRecording = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start recording: $e')));
      return;
    }

    if (!mounted) return;

    _exportTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _exportService?.exportSegment(),
    );

    if (_isDemoMode) {
      _demoAccumulatedText = _liveTranscript;
      _demoCurrentActiveText = "";
      final allSections = chapter4_1TranscriptData
          .expand((page) => page.sections)
          .toList();
      if (_demoSectionIndex >= allSections.length) {
        _demoSectionIndex = 0;
      }
      _startDemoTyping();
    } else {
      try {
        final token = await _authService.getTemporaryToken();
        await _speechService.startListening(token);
      } catch (e) {
        _exportTimer?.cancel();
        _exportTimer = null;
        _realtimeAgentCoordinator?.dispose();
        _realtimeAgentCoordinator = null;
        await _studentAttentionTracker.stop();
        _exportService = null;
        if (!mounted) return;
        setState(() {
          _isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get Azure token: $e')),
        );
      }
    }
  }

  List<String> _getTypingIncrements(String text) {
    final List<String> increments = [];
    int i = 0;
    while (i < text.length) {
      final char = text[i];
      if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        final buffer = StringBuffer();
        while (i < text.length &&
            RegExp(r'[a-zA-Z0-9\-\.\u0027]').hasMatch(text[i])) {
          buffer.write(text[i]);
          i++;
        }
        if (i < text.length && text[i] == ' ') {
          buffer.write(' ');
          i++;
        }
        increments.add(buffer.toString());
      } else {
        if (i + 1 < text.length &&
            !RegExp(r'[a-zA-Z0-9]').hasMatch(text[i + 1])) {
          increments.add(text.substring(i, i + 2));
          i += 2;
        } else {
          increments.add(text.substring(i, i + 1));
          i++;
        }
      }
    }
    return increments;
  }

  void _startDemoTyping() {
    final allSections = chapter4_1TranscriptData
        .expand((page) => page.sections)
        .toList();
    if (_demoSectionIndex >= allSections.length) {
      unawaited(_handleRecordingToggle());
      return;
    }

    final content = allSections[_demoSectionIndex].content;
    _demoIncrements = _getTypingIncrements(content);
    _demoIncrementIndex = 0;
    _demoCurrentActiveText = "";

    _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isRecording) {
        timer.cancel();
        return;
      }

      if (_demoIncrementIndex < _demoIncrements.length) {
        _demoCurrentActiveText += _demoIncrements[_demoIncrementIndex];
        _demoIncrementIndex++;
        setState(() {
          if (_demoAccumulatedText.isEmpty) {
            _liveTranscript = _demoCurrentActiveText;
          } else {
            _liveTranscript =
                '$_demoAccumulatedText\n\n$_demoCurrentActiveText';
          }
        });
        _exportService?.tick(_liveTranscript);
      } else {
        timer.cancel();
        _demoAccumulatedText = _demoAccumulatedText.isEmpty
            ? _demoCurrentActiveText
            : '$_demoAccumulatedText\n\n$_demoCurrentActiveText';
        _demoCurrentActiveText = "";
        _demoSectionIndex++;

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _isRecording) {
            _startDemoTyping();
          }
        });
      }
    });
  }

  void _stopDemoTyping() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  Future<void> _handlePdfUploaded(String pdfPath) async {
    setState(() {
      _showSummary = true;
      _layoutOrder.remove('summary');
      _layoutOrder.add('summary');
    });

    try {
      await _userIdentityService.ensureSignedIn();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize user memory: $error')),
      );
      return;
    }
    await _notesViewModel.generateFromPdf(
      storageId: widget.fileId,
      pdfPath: pdfPath,
      courseId: widget.courseId,
      lectureId: widget.fileId,
    );
  }

  void _retryGeneratingNotes() {
    unawaited(_notesViewModel.retry(widget.fileId));
  }

  Widget _buildPanel(
    String id,
    double width,
    int index,
    String? nextId,
    double totalWeight,
    double maxWidth,
  ) {
    Widget panel;
    switch (id) {
      case "slides":
        panel = SlidesPanel(
          key: _slidesPanelKey,
          width: width,
          index: index,
          fileId: widget.fileId,
          onClose: () => setState(() => _showSlides = false),
          onPdfUploaded: _handlePdfUploaded,
          segmentStream: _segmentStreamController.stream,
          currentPageNotifier: _currentPageNotifier,
        );
        break;
      case "transcript":
        panel = TranscriptPanel(
          key: const ValueKey("transcript"),
          width: width,
          index: index,
          onClose: () => setState(() => _showTranscript = false),
          isRecording: _isRecording,
          savedStatusText: _savedStatusText,
          onStartRecording: () {
            unawaited(_handleRecordingToggle());
          },
          liveTranscript: _liveTranscript,
          isDemoMode: _isDemoMode,
          onDemoModeChanged: (val) {
            setState(() {
              _isDemoMode = val;
            });
          },
        );
        break;
      case "summary":
        panel = SummaryPanel(
          key: const ValueKey("summary"),
          width: width,
          index: index,
          onClose: () => setState(() => _showSummary = false),
          notes: _notesViewModel.notes,
          isGenerating: _notesViewModel.isGenerating,
          errorMessage: _notesViewModel.errorMessage,
          totalPages: _notesViewModel.totalPages,
          completedPages: _notesViewModel.completedPages,
          totalBatches: _notesViewModel.totalBatches,
          completedBatches: _notesViewModel.completedBatches,
          onRetry: _notesViewModel.canRetry ? _retryGeneratingNotes : null,
          segmentStream: _segmentStreamController.stream,
        );
        break;
      case "chatbot":
        final notesString = _notesViewModel.notes
            .map((page) => page.markdown)
            .join("\n\n");

        panel = ChatbotPanel(
          key: const ValueKey("chatbot"),
          width: width,
          index: index,
          onClose: () => setState(() => _showChatbot = false),
          notebookId: int.tryParse(widget.fileId) ?? 0,
          courseId: widget.courseId,
          lectureId: widget.fileId,
          aiNotes: notesString, // 目前畫面上最新最真實的筆記內容
          transcript: _liveTranscript, // 目前最新錄製的即時逐字稿
          segmentStream: _segmentStreamController.stream,
        );
        break;
      default:
        return const SizedBox.shrink();
    }

    if (nextId == null) {
      return SizedBox(key: ValueKey(id), width: width, child: panel);
    }

    return SizedBox(
      key: ValueKey(id),
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          panel,
          Positioned(
            // lever for adjusting the size of the panels
            right: -8,
            top: 0,
            bottom: 0,
            width: 16,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    List<String> visibleIds = [];
                    for (var vid in _layoutOrder) {
                      if ((vid == 'slides' && _showSlides) ||
                          (vid == 'transcript' && _showTranscript) ||
                          (vid == 'summary' && _showSummary) ||
                          (vid == 'chatbot' && _showChatbot)) {
                        visibleIds.add(vid);
                      }
                    }
                    double sumMinW = 0;
                    double totalWeightOfVisible = 0;
                    for (var vid in visibleIds) {
                      sumMinW += _getMinWidth(vid);
                      totalWeightOfVisible += _panelWeights[vid]!;
                    }
                    double remainingSpace = maxWidth - sumMinW;

                    double weightDelta = remainingSpace > 0
                        ? (details.delta.dx / remainingSpace) *
                              totalWeightOfVisible
                        : 0;

                    double newLeftWeight = _panelWeights[id]! + weightDelta;
                    double newRightWeight =
                        _panelWeights[nextId]! - weightDelta;

                    double minLeft = _getMinWidth(id);
                    double minRight = _getMinWidth(nextId);
                    double newLeftWidth =
                        minLeft +
                        (remainingSpace > 0
                            ? remainingSpace *
                                  (newLeftWeight / totalWeightOfVisible)
                            : 0);
                    double newRightWidth =
                        minRight +
                        (remainingSpace > 0
                            ? remainingSpace *
                                  (newRightWeight / totalWeightOfVisible)
                            : 0);

                    if (newLeftWidth >= minLeft &&
                        newRightWidth >= minRight &&
                        newLeftWeight >= 0 &&
                        newRightWeight >= 0) {
                      _panelWeights[id] = newLeftWeight;
                      _panelWeights[nextId] = newRightWeight;
                    }
                  });
                },
                child: Center(
                  child: Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCD7C9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFF5F2EA) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF8E9775).withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: isActive ? const Color(0xFF8E9775) : const Color(0xFFA8A08E),
            size: 24,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                key: _panelsAreaKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double totalWeight = 0;
                    for (var id in _layoutOrder) {
                      if ((id == 'slides' && _showSlides) ||
                          (id == 'transcript' && _showTranscript) ||
                          (id == 'summary' && _showSummary) ||
                          (id == 'chatbot' && _showChatbot)) {
                        totalWeight += _panelWeights[id]!;
                      }
                    }

                    if (totalWeight == 0) {
                      return const Center(child: Text("No panels selected"));
                    }

                    // Build visible panels
                    List<String> visibleIds = [];
                    for (var id in _layoutOrder) {
                      if ((id == 'slides' && _showSlides) ||
                          (id == 'transcript' && _showTranscript) ||
                          (id == 'summary' && _showSummary) ||
                          (id == 'chatbot' && _showChatbot)) {
                        visibleIds.add(id);
                      }
                    }

                    // Calculate sum of minimum widths
                    double sumMinW = 0;
                    for (var id in visibleIds) {
                      sumMinW += _getMinWidth(id);
                    }

                    // Calculate actual widths proportionally
                    Map<String, double> calculatedWidths = {};
                    if (constraints.maxWidth <= sumMinW) {
                      // deal with the condition when user activate split screen. under this circumstance we wouldn't close the panel for him. we would instead let the user scroll the panels horizontally
                      for (var id in visibleIds) {
                        calculatedWidths[id] = _getMinWidth(id);
                      }
                    } else {
                      double remainingSpace = constraints.maxWidth - sumMinW;
                      double totalWeightOfVisible = 0;
                      for (var id in visibleIds) {
                        totalWeightOfVisible += _panelWeights[id]!;
                      }
                      for (var id in visibleIds) {
                        double extra = totalWeightOfVisible > 0
                            ? remainingSpace *
                                  (_panelWeights[id]! / totalWeightOfVisible)
                            : 0;
                        calculatedWidths[id] = _getMinWidth(id) + extra;
                      }
                    }

                    List<Widget> visiblePanels = [];
                    for (int i = 0; i < visibleIds.length; i++) {
                      String id = visibleIds[i];
                      String? nextId = (i < visibleIds.length - 1)
                          ? visibleIds[i + 1]
                          : null;
                      double width = calculatedWidths[id]!;

                      visiblePanels.add(
                        _buildPanel(
                          id,
                          width,
                          i,
                          nextId,
                          totalWeight,
                          constraints.maxWidth,
                        ),
                      );
                    }

                    return ReorderableListView(
                      scrollDirection: Axis.horizontal,
                      onReorder: _reorder,
                      buildDefaultDragHandles: false, // Use our custom handle
                      children: visiblePanels,
                    );
                  },
                ),
              ),
              Container(
                width: 80,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(left: BorderSide(color: Color(0xFFEAE7DC))),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 12,
                ),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Color(0xFFA8A08E),
                            ),
                            onPressed: () => context.pop(),
                          ),
                          const SizedBox(height: 32),
                          _buildSidebarButton(
                            icon: Icons.picture_in_picture,
                            isActive: _showSlides,
                            onPressed: () => _togglePanel('slides'),
                          ),
                          const SizedBox(height: 16),
                          _buildSidebarButton(
                            icon: Icons.subtitles,
                            isActive: _showTranscript,
                            onPressed: () => _togglePanel('transcript'),
                          ),
                          const SizedBox(height: 16),
                          _buildSidebarButton(
                            icon: Icons.auto_awesome,
                            isActive: _showSummary,
                            onPressed: () => _togglePanel('summary'),
                          ),
                          const SizedBox(height: 16),
                          _buildSidebarButton(
                            icon: Icons.chat_bubble_outline,
                            isActive: _showChatbot,
                            onPressed: () => _togglePanel('chatbot'),
                          ),
                          const Spacer(),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F2EA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFEAE7DC),
                              ),
                            ),
                            child: PopupMenuButton<String>(
                              initialValue: _currentLanguage,
                              tooltip: 'Select Language',
                              onSelected: (val) {
                                setState(() => _currentLanguage = val);
                                _speechService.setLocale(val);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'en_US',
                                  child: Text('English'),
                                ),
                                const PopupMenuItem(
                                  value: 'zh_TW',
                                  child: Text('中文 (台灣)'),
                                ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.language,
                                      color: Color(0xFF8E9775),
                                      size: 20,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _currentLanguage == 'en_US' ? 'EN' : 'TW',
                                      style: const TextStyle(
                                        color: Color(0xFF8E9775),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              unawaited(_handleRecordingToggle());
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              backgroundColor: _isRecording
                                  ? Colors.red.shade50
                                  : const Color(0xFF8E9775),
                              foregroundColor: _isRecording
                                  ? Colors.red
                                  : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop : Icons.mic,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
