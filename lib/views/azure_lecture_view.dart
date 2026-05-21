import 'package:flutter/material.dart';
import '../services/azure_speech_service.dart';
import '../services/auth_service.dart';

class AzureLectureView extends StatefulWidget {
  const AzureLectureView({Key? key}) : super(key: key);

  @override
  State<AzureLectureView> createState() => _AzureLectureViewState();
}

class _AzureLectureViewState extends State<AzureLectureView> {
  final AzureSpeechService _speechService = AzureSpeechService();
  final AzureAuthService _authService = AzureAuthService();
  bool _isLoadingToken = false;

  @override
  void dispose() {
    _speechService.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_speechService.isListening) {
      await _speechService.stopListening();
    } else {
      setState(() {
        _isLoadingToken = true;
      });
      try {
        // 1. Fetch token securely from your backend
        final token = await _authService.getTemporaryToken();
        
        // 2. Start listening with the token
        await _speechService.startListening(token);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingToken = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Azure Secure STT Lecture'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // The StreamBuilder ensures that only this text block rebuilds 
              // as new transcriptions arrive, preventing full page jank.
              child: Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: StreamBuilder<String>(
                    stream: _speechService.transcriptStream,
                    initialData: "Tap the microphone to start...",
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
                      }
                      
                      return Text(
                        snapshot.data ?? "",
                        style: const TextStyle(fontSize: 18.0, height: 1.5),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              // StreamBuilder for the button to react to listening status changes
              child: StreamBuilder<bool>(
                stream: _speechService.statusStream,
                initialData: false,
                builder: (context, snapshot) {
                  final isListening = snapshot.data ?? false;
                  return FloatingActionButton.extended(
                    onPressed: _isLoadingToken ? null : _toggleListening,
                    backgroundColor: isListening ? Colors.red : Colors.blue,
                    icon: _isLoadingToken 
                      ? const SizedBox(
                          width: 24, 
                          height: 24, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : Icon(isListening ? Icons.stop : Icons.mic),
                    label: Text(
                      _isLoadingToken 
                        ? 'Connecting...' 
                        : isListening ? 'Stop Recording' : 'Start Recording'
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
