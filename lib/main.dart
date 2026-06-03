import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'screens/dashboard.dart';
import 'screens/course_details.dart';
import 'screens/lecture_view.dart';
import 'widgets/layout_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }
  runApp(const MyApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return LayoutWrapper(currentPath: state.uri.path, child: child);
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Dashboard()),
        GoRoute(
          path: '/course/:courseId',
          builder: (context, state) {
            final courseId = state.pathParameters['courseId']!;
            return CourseDetails(courseId: courseId);
          },
        ),
        GoRoute(
          path: '/lecture/:courseId/:fileId',
          builder: (context, state) {
            final courseId = state.pathParameters['courseId']!;
            final fileId = state.pathParameters['fileId']!;
            return LectureView(courseId: courseId, fileId: fileId);
          },
        ),
      ],
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Claw-Note',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFDFCF8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8E9775),
          primary: const Color(0xFF8E9775),
          surface: const Color(0xFFFDFCF8),
          onSurface: const Color(0xFF3D3D3D),
        ),
        fontFamily: 'Inter', // Default sans-serif
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Color(0xFFA8A08E)),
          titleTextStyle: TextStyle(
            color: Color(0xFF3D3D3D),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
