import 'package:flutter/material.dart';

class SlidePage extends StatelessWidget {
  final int pageNumber;
  final Widget child;

  const SlidePage({super.key, required this.pageNumber, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 48),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Slide Container
          Container(
            width: double.infinity,
            height: 480,
            constraints: const BoxConstraints(maxWidth: 850),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFEAE7DC), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top decoration line
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E9775).withOpacity(0.2),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(22),
                        topRight: Radius.circular(22),
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Center(child: child),
                ),
                // Bottom-right watermark
                Positioned(
                  bottom: 32,
                  right: 48,
                  child: Row(
                    children: [
                      Text(
                        'Computer Architecture • Autumn 2023'.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                          color: Color(0xFFA8A08E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Left vertical text
          Positioned(
            left: -60,
            top: 40,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                "SLIDE \${pageNumber.toString().padLeft(2, '0')}",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8E9775).withOpacity(0.3),
                  letterSpacing: 4.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
