import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../widgets/slides_panel.dart';
import '../widgets/transcript_panel.dart';
import '../widgets/summary_panel.dart';
import '../widgets/chatbot_panel.dart';
import '../services/speech_service.dart';

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

  late SpeechService _speechService;
  String _liveTranscript = '';
  String _currentLanguage = 'en_US';
  String? _savedFilePath;
  double _soundLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _speechService = SpeechService(
      onUpdate: (text, listening) {
        setState(() {
          _liveTranscript = text;
          _isRecording = listening;
        });
      },
      onSoundLevelChange: (level) {
        setState(() {
          _soundLevel = level;
        });
      },
      onError: (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      },
    );
    _speechService.initialize();
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

  List<String> _layoutOrder = ["slides", "transcript", "summary", "chatbot"];

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
          key: const ValueKey("slides"),
          width: width,
          index: index,
          onClose: () => setState(() => _showSlides = false),
        );
        break;
      case "transcript":
        panel = TranscriptPanel(
          key: const ValueKey("transcript"),
          width: width,
          index: index,
          onClose: () => setState(() => _showTranscript = false),
          isRecording: _isRecording,
          onStartRecording: () => setState(() => _isRecording = true),
          liveTranscript: _liveTranscript,
        );
        break;
      case "summary":
        panel = SummaryPanel(
          key: const ValueKey("summary"),
          width: width,
          index: index,
          onClose: () => setState(() => _showSummary = false),
        );
        break;
      case "chatbot":
        panel = ChatbotPanel(
          key: const ValueKey("chatbot"),
          width: width,
          index: index,
          onClose: () => setState(() => _showChatbot = false),
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
                ? const Color(0xFF8E9775).withOpacity(0.3)
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
                            onPressed: () async {
                              if (_isRecording) {
                                _speechService.toggleListening();
                                final dir =
                                    await getApplicationDocumentsDirectory();
                                final file = File(
                                  '${dir.path}/transcript_test.json',
                                );
                                await file.writeAsString(
                                  _speechService.getExportJson(),
                                );
                                setState(() {
                                  _savedFilePath = file.path;
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Saved to ${file.path}'),
                                    ),
                                  );
                                }

                                Future.delayed(const Duration(seconds: 3), () {
                                  if (mounted) {
                                    setState(() {
                                      _savedFilePath = null;
                                    });
                                  }
                                });
                              } else {
                                setState(() {
                                  _savedFilePath = null;
                                  _liveTranscript = '';
                                  _soundLevel = 0.0;
                                });
                                _speechService.reset();
                                _speechService.toggleListening();
                              }
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
