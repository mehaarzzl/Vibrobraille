import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'braille_engine/braille_translator.dart';
import 'braille_engine/temporal_encoder.dart';
import 'braille_engine/word_scheduler.dart';
import 'socket_client/socket_manager.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => BrailleTranslator()),
        Provider(create: (_) => TemporalEncoder()),
      ],
      child: const VibroApp(),
    ),
  );
}

class VibroApp extends StatelessWidget {
  const VibroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const DemoTelemetryScreen(),
    );
  }
}

class DemoTelemetryScreen extends StatefulWidget {
  const DemoTelemetryScreen({super.key});

  @override
  State<DemoTelemetryScreen> createState() => _DemoTelemetryScreenState();
}

class _DemoTelemetryScreenState extends State<DemoTelemetryScreen> {
  late SocketManager socketManager;
  late WordScheduler wordScheduler;
  String status = "Disconnected";
  String fullSentence = "Ready to receive tactile stream...";
  String currentWord = "";
  double speed = 1.0;
  final TextEditingController _ipController =
      TextEditingController(text: "192.168.0.103");

  @override
  void initState() {
    super.initState();
    wordScheduler = WordScheduler(
      translator: context.read<BrailleTranslator>(),
      encoder: context.read<TemporalEncoder>(),
      onWordRendered: (word) {
        setState(() => currentWord = word);
      },
    );

    socketManager = SocketManager(
      url: 'ws://192.168.0.103:3000',
      onEventReceived: (data) {
        _handleEvent(data);
      },
      onConnected: () => setState(() => status = "Connected"),
      onDisconnected: () => setState(() => status = "Disconnected"),
    );
  }

  void _handleEvent(Map<String, dynamic> data) async {
    print("🔥 WS EVENT RECEIVED: ${data['type']} - ${data.toString()}");

    switch (data['type']) {
      case 'SET_SENTENCE':
        print("📝 Setting sentence: ${data['value']}");
        setState(() {
          fullSentence = data['value'];
          currentWord = "";
        });
        break;
      case 'WORD':
        print("📣 Scheduling word: ${data['value']}");
        await wordScheduler.scheduleWord(data['value']);
        break;
      case 'SENTENCE_END':
        print("🔚 Sentence end");
        await wordScheduler.scheduleSentenceEnd();
        break;
      case 'PARAGRAPH_END':
        print("📄 Paragraph end");
        await wordScheduler.scheduleParagraphEnd();
        break;
      default:
        print("❓ Unknown event type: ${data['type']}");
    }
  }

  void _showConnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Connect to AI Brain",
            style: TextStyle(color: Colors.cyan)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter the IP address of your PC:",
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "e.g. 192.168.1.10",
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyan)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            onPressed: () {
              final ip = _ipController.text.trim();
              if (ip.isNotEmpty) {
                socketManager.connect("MOCK-SESSION-123",
                    newUrl: "ws://$ip:3000");
              }
              Navigator.pop(context);
            },
            child: const Text("CONNECT", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  /// Builds the rich text for karaoke highlighting
  Widget _buildKaraokeText() {
    if (currentWord.isEmpty) {
      return Text(fullSentence,
          style: const TextStyle(color: Colors.white24, fontSize: 32));
    }

    final words = fullSentence.split(' ');
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
        children: words.map((word) {
          // Robust comparison ignoring punctuation/case
          final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
          final cleanCurrent =
              currentWord.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
          final isCurrent = cleanWord == cleanCurrent;

          return TextSpan(
            text: "$word ",
            style: TextStyle(
              color: isCurrent ? Colors.cyan : Colors.white24,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              shadows: isCurrent
                  ? [const Shadow(color: Colors.cyan, blurRadius: 20)]
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  int _pointerCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) => _pointerCount++,
        onPointerUp: (_) {
          // Detect multi-finger gestures on release
          if (_pointerCount == 2) socketManager.sendSignal("NEXT");
          if (_pointerCount == 3) socketManager.sendSignal("PREVIOUS");
          _pointerCount = 0;
        },
        child: GestureDetector(
          onLongPress: () => socketManager.sendSignal("REPEAT"),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle,
                            color: status == "Connected"
                                ? Colors.green
                                : Colors.red,
                            size: 12),
                        const SizedBox(width: 8),
                        Text(
                          status == "Connected"
                              ? "Connected to AI Brain"
                              : "Disconnected",
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
                const Text(
                  "Streaming tactile words...",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
                _buildKaraokeText(),
                const SizedBox(height: 40),
                Text(
                  currentWord,
                  style: const TextStyle(
                    color: Colors.cyan,
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -2,
                    shadows: [Shadow(color: Colors.cyan, blurRadius: 40)],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.grey, size: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: speed,
                        min: 0.25,
                        max: 2.0,
                        divisions: 7,
                        activeColor: Colors.cyan,
                        onChanged: (val) {
                          setState(() => speed = val);
                          socketManager.sendSignalWithData("SPEED", val);
                        },
                      ),
                    ),
                    Text(
                      "${speed}x",
                      style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: status == "Disconnected"
          ? FloatingActionButton(
              backgroundColor: Colors.cyan,
              onPressed: _showConnectDialog,
              child: const Icon(Icons.link, color: Colors.black),
            )
          : null,
    );
  }
}
