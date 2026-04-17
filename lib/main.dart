import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// --- ADB Manager ---
class AdbManager extends ChangeNotifier {
  bool isConnected = false;
  bool isRemoteActive = false;
  String status = "iPhone 17 Optimized";
  List<String> logs = [];
  Offset? lastTap;

  void log(String message) {
    logs.add("[${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}] $message");
    status = message;
    notifyListeners();
  }

  void startDemoConnection(String ip) {
    log("Đang bắt tay với $ip...");
    Future.delayed(const Duration(seconds: 1), () {
      isConnected = true;
      log("KẾT NỐI THÀNH CÔNG!");
      notifyListeners();
    });
  }

  void disconnect() {
    isConnected = false;
    isRemoteActive = false;
    log("Hệ thống đã ngắt kết nối.");
    notifyListeners();
  }

  void runCommand(String name, String cmd) {
    log("Chạy: $name...");
    Future.delayed(const Duration(milliseconds: 600), () => log("Xong: $cmd"));
  }

  void toggleRemote() {
    isRemoteActive = !isRemoteActive;
    SystemChrome.setPreferredOrientations(isRemoteActive 
      ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] 
      : [DeviceOrientation.portraitUp]);
    notifyListeners();
  }

  void simulateTap(Offset pos) {
    lastTap = pos;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 300), () {
      lastTap = null;
      notifyListeners();
    });
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(ChangeNotifierProvider(create: (_) => AdbManager(), child: const AdbApp()));
}

class AdbApp extends StatelessWidget {
  const AdbApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020617),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ), 
      home: const Dashboard()
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final adb = Provider.of<AdbManager>(context);
    final ctrl = TextEditingController(text: "192.168.1.100");

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: adb.isRemoteActive 
                ? _buildRemote(adb, context) 
                : _buildHome(adb, ctrl, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned(top: -150, left: -50, child: _blurOrb(const Color(0xFF1E40AF), 400)),
        Positioned(bottom: -150, right: -50, child: _blurOrb(const Color(0xFF701A75), 400)),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
          child: Container(color: Colors.transparent),
        ),
      ],
    );
  }

  Widget _buildHome(AdbManager adb, TextEditingController ctrl, BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey("home"),
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            const SizedBox(height: 30),
            _buildHeader(),
            const SizedBox(height: 40),
            _buildPulseIcon(adb.isConnected),
            const SizedBox(height: 40),
            
            // Connection Area
            _glassPanel(
              child: Column(
                children: [
                  TextField(
                    controller: ctrl, 
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(border: InputBorder.none, icon: Icon(Icons.wifi_tethering, color: Colors.blueAccent), hintText: "IP Android"),
                  ),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  if (adb.isConnected)
                    Row(
                      children: [
                        Expanded(child: _actionButton("REMOTE", Colors.green, adb.toggleRemote)),
                        const SizedBox(width: 12),
                        Expanded(child: _actionButton("EXIT", Colors.redAccent.withOpacity(0.8), adb.disconnect)),
                      ],
                    )
                  else
                    _actionButton("BẮT ĐẦU KẾT NỐI", Colors.blueAccent, () => adb.startDemoConnection(ctrl.text)),
                ],
              ),
            ),

            const SizedBox(height: 24),
            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              child: adb.isConnected ? _buildActionsHub(adb) : const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),
            _buildTerminal(adb),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsHub(AdbManager adb) {
    return Column(
      children: [
        _sectionTitle("TRUNG TÂM ĐIỀU KHIỂN"),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            _actionCard(0, Icons.auto_mode_rounded, "UPDATE KDS", Colors.orange),
            _actionCard(1, Icons.app_registration_rounded, "CÀI ĐẶT APK", Colors.purpleAccent),
            _actionCard(2, Icons.screenshot_monitor_rounded, "CHỤP MÀN", Colors.cyanAccent),
            _actionCard(3, Icons.refresh_rounded, "REBOOT", Colors.redAccent),
          ],
        ),
      ],
    );
  }

  Widget _buildRemote(AdbManager adb, BuildContext context) {
    return Row(
      key: const ValueKey("remote"),
      children: [
        _buildRemoteSidebar(adb),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: GestureDetector(
              onTapDown: (d) => adb.simulateTap(d.localPosition),
              child: _glassPanel(
                padding: EdgeInsets.zero,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.mobile_off_rounded, size: 80, color: Colors.white10),
                    if (adb.lastTap != null) _buildTapIndicator(adb.lastTap!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteSidebar(AdbManager adb) {
    return Container(
      width: 70,
      decoration: const BoxDecoration(color: Colors.black26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: const Icon(Icons.close_rounded, color: Colors.redAccent), onPressed: () => adb.toggleRemote()),
          const Icon(Icons.home_max_rounded, color: Colors.white38),
          const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white38),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---
  Widget _buildHeader() => Column(children: [Text("ADB TOOLBOX", style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)), const Text("iPHONE 17 PRO MAX EDITION", style: TextStyle(color: Colors.blueAccent, letterSpacing: 3, fontSize: 9, fontWeight: FontWeight.bold))]);
  
  Widget _buildPulseIcon(bool isConnected) => AnimatedContainer(
    duration: const Duration(milliseconds: 500),
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      shape: BoxShape.circle, 
      border: Border.all(color: isConnected ? Colors.greenAccent : Colors.blueAccent, width: 2),
      boxShadow: [BoxShadow(color: (isConnected ? Colors.green : Colors.blue).withOpacity(0.15), blurRadius: 30, spreadRadius: 10)],
    ),
    child: Icon(isConnected ? Icons.link : Icons.link_off, size: 40, color: isConnected ? Colors.greenAccent : Colors.blueAccent),
  );

  Widget _sectionTitle(String title) => Row(children: [Container(width: 3, height: 14, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1))]);

  Widget _actionCard(int index, IconData icon, String label, Color color) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 150)),
      builder: (context, double v, child) => Transform.scale(scale: 0.8 + (0.2 * v), child: Opacity(opacity: v, child: child)),
      child: Container(
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 18, color: color), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  Widget _actionButton(String text, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))]), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
  );

  Widget _glassPanel({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.03), 
      borderRadius: BorderRadius.circular(24), 
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    child: child,
  );

  Widget _buildTerminal(AdbManager adb) => Container(
    height: 100, width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
    child: ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: adb.logs.length, 
      itemBuilder: (context, i) => Text(adb.logs[i], style: GoogleFonts.firaCode(fontSize: 10, color: Colors.blueAccent.withOpacity(0.6))),
    ),
  );

  Widget _buildTapIndicator(Offset pos) => TweenAnimationBuilder(
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 300),
    builder: (context, double v, _) => Positioned(
      left: pos.dx - 20, top: pos.dy - 20,
      child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(1 - v), width: 3 * (1 - v)))),
    ),
  );

  Widget _blurOrb(Color c, double size) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: c));
}
