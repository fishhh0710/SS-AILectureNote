import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_note_app/services/student_attention_tracker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('tracks page duration, history, and lifecycle state', () async {
    var now = DateTime.utc(2026, 6, 15, 4);
    final page = ValueNotifier<int>(1);
    final tracker = StudentAttentionTracker(
      currentPageNotifier: page,
      now: () => now,
    );

    await tracker.start('attention-test-session');
    now = now.add(const Duration(seconds: 12));
    page.value = 2;
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(seconds: 35));
    tracker.didChangeAppLifecycleState(AppLifecycleState.paused);
    final snapshot = tracker.snapshot();

    expect(snapshot['currentPage'], 2);
    expect(snapshot['currentPageDurationSeconds'], 35);
    expect(snapshot['appLifecycle'], 'background');
    expect(snapshot['backgroundedAt'], isNotNull);
    expect(tracker.history.single['page'], 1);
    expect(tracker.history.single['durationSeconds'], 12);

    await tracker.stop();
    page.dispose();
  });
}
