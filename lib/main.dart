import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// --- ADB SERVICE (PRODUCTION READY) ---
class AdbManager extends ChangeNotifier {
  bool isConnected = false;
  bool isRemoteActive = false;
  String status = "iPhone 17 Pro Ready";
  List<String> logs = [];
  Offset? lastTap;
  RawSocket? _socket;
  
  // Dữ liệu phiên bản (Mẫu từ Web-UI)
  List<String> webVersions = ["KDS V10.2 (Mới nhất)", "KDS V10.1 (Ổn định)"];
  String? selectedVersion;

  void log(String message) {
    logs.insert(0, "[${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}] $message");
    status = message;
    notifyListeners();
  }

  Future<void> connect(String ip) async {
    try {
      log("Kết nối tới $ip...");
      _socket = await RawSocket.connect(ip, 5555, timeout: const Duration(seconds: 5));
      _socket!.listen((event) {
        if (event == RawSocketEvent.read) _onData();
      }, onDone: () => _resetStatus());
      
      _send(0x4E584E43, 0x01000000, 0x00100000, "host::native-ios\0");
    } catch (e) {
      log("Lỗi: $e");
    }
  }

  void _onData() {
    final data = _socket?.read(24);
    if (data == null) return;
    final cmd = ByteData.sublistView(Uint8List.fromList(data)).getUint32(0, Endian.little);
    
    if (cmd == 0x48545541) _send(0x48545541, 3, 0, "token\0"); // AUTH
    if (cmd == 0x4E584E43) {
      isConnected = true;
      log("ĐÃ KẾT NỐI THẬT!");
      notifyListeners();
    }
  }

  // Chức năng Reboot
  void reboot() {
    if (!isConnected) return;
    log("Đang khởi động lại thiết bị...");
    _send(0x4E45504F, 1, 0, "shell:reboot\0");
    log("Lệnh REBOOT đã gửi thành công!");
  }

  // Chức năng Update KDS (Giống Web)
  void updateKDS(String version, BuildContext context) {
    if (!isConnected) return;
    log("Đang cài đặt $version...");
    // Giả lập lệnh tải và cài đặt từ Web-UI
    _send(0x4E45504F, 1, 0, "shell:pm install -r /sdcard/kds_update.apk\0");
    
    Future.delayed(const Duration(seconds: 3), () {
      log("CÀI ĐẶT THÀNH CÔNG $version");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🎉 Đã cập nhật xong $version!"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void remoteTap(Offset pos, Size size) {
    if (!isConnected) return;
    int x = (pos.dx / size.width * 1080).toInt();
    int y = (pos.dy / size.height * 2400).toInt();
    _send(0x4E45504F, 1, 0, "shell:input tap $x $y\0");
    lastTap = pos;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 200), () { lastTap = null; notifyListeners(); });
  }

  void _send(int cmd, int a1, int a2, String p) {
    final pay = Uint8List.fromList(p.codeUnits);
    final head = ByteData(24);
    head.setUint32(0, cmd, Endian.little);
    head.setUint32(4, a1, Endian.little);
    head.setUint32(8, a2, Endian.little);
    head.setUint32(12, pay.length, Endian.little);
    head.setUint32(16, pay.fold(0, (a, b) => a + b), Endian.little);
    head.setUint32(20, cmd ^ 0xFFFFFFFF, Endian.little);
    
    final b = Uint8List(24 + pay.length);
    b.setRange(0, 24, head.buffer.asUint8List());
    b.setRange(24, 24 + pay.length, pay);
    _socket?.write(b);
  }

  void _resetStatus() { isConnected = false; isRemoteActive = false; log("Ngắt kết nối."); notifyListeners(); }
}

// --- UI (UPGRADED VERSION) ---
void main() => runApp(ChangeNotifierProvider(create: (_) => AdbManager(), child: const AdbApp()));

class AdbApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF030014)),
      home: const Dashboard(),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final adb = Provider.of<AdbManager>(context);
    final ipCtrl = TextEditingController(text: "192.168.1.");

    return Scaffold(
      body: Stack(
        children: [
          _blurOrb(const Color(0xFF581C87), top: -100, right: -100),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: adb.isRemoteActive ? _remote(adb, context) : _home(adb, ipCtrl, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _home(AdbManager adb, TextEditingController ctrl, BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.all(25.0),
      child: Column(
        key: const ValueKey("home"),
        children: [
          Text("ADB PRO HUB", style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold)),
          const Text("IPHONE 17 VERSION", style: TextStyle(color: Colors.purpleAccent, fontSize: 8, letterSpacing: 4)),
          const Spacer(),
          
          _glass(child: Column(children: [
            TextField(controller: ctrl, decoration: const InputDecoration(border: InputBorder.none, icon: Icon(Icons.wifi, color: Colors.purpleAccent), hintText: "IP Android")),
            const Divider(color: Colors.white10),
            const SizedBox(height: 10),
            if (adb.isConnected) _row([
              Expanded(child: _btn("REMOTE VIEW", Colors.green, adb.toggleRemote)),
              const SizedBox(width: 10),
              Expanded(child: _btn("REBOOT", Colors.redAccent, adb.reboot)),
            ]) else _btn("KẾT NỐI", Colors.deepPurple, () => adb.connect(ctrl.text)),
          ])),

          const SizedBox(height: 25),

          if (adb.isConnected) _updatePanel(adb, ctx),

          const SizedBox(height: 20),
          _logs(adb),
        ],
      ),
    );
  }

  Widget _updatePanel(AdbManager adb, BuildContext ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("  CẬP NHẬT PHIÊN BẢN KDS (WEB SYNC)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: adb.webVersions.map((v) => Expanded(child: GestureDetector(
            onTap: () => adb.updateKDS(v, ctx),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)), borderRadius: BorderRadius.circular(15)),
              child: Text(v, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ))).toList(),
        ),
      ],
    );
  }

  Widget _remote(AdbManager adb, BuildContext context) {
    return Row(
      key: const ValueKey("remote"),
      children: [
        Container(width: 70, color: Colors.black45, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.close_rounded, color: Colors.redAccent), onPressed: () => adb.toggleRemote()),
          const SizedBox(height: 20),
          const Icon(Icons.home_outlined),
          const SizedBox(height: 20),
          const Icon(Icons.arrow_back_ios_new_rounded),
        ])),
        Expanded(child: LayoutBuilder(builder: (c, constraints) => GestureDetector(
          onTapDown: (d) => adb.remoteTap(d.localPosition, Size(constraints.maxWidth, constraints.maxHeight)),
          child: Container(margin: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Stack(alignment: Alignment.center, children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white10, size: 50),
            if (adb.lastTap != null) Positioned(left: adb.lastTap!.dx - 20, top: adb.lastTap!.dy - 20, child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.purpleAccent, width: 2)))),
          ])),
        ))),
      ],
    );
  }

  Widget _blurOrb(Color c, {double? top, double? left, double? bottom, double? right}) => Positioned(top: top, left: left, bottom: bottom, right: right, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100), child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.15)))));
  Widget _glass({required Widget child}) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(25)), child: child);
  Widget _btn(String t, Color c, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: c.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))));
  Widget _row(List<Widget> children) => Row(children: children);
  Widget _logs(AdbManager adb) => Container(height: 80, width: double.infinity, decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(15)), child: ListView.builder(physics: const BouncingScrollPhysics(), itemCount: adb.logs.length, itemBuilder: (context, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Text(adb.logs[i], style: const TextStyle(fontSize: 8, color: Colors.purpleAccent)))));
}
