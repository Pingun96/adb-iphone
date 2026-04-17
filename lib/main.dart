import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// --- BỘ NÃO ADB THẬT (REAL ADB ENGINE) ---
class AdbManager extends ChangeNotifier {
  bool isConnected = false;
  bool isRemoteActive = false;
  String status = "iPhone 17 Pro Ready";
  List<String> logs = [];
  Offset? lastTap;
  RawSocket? _socket;
  
  // Thông tin thiết bị thực tế
  String? deviceModel;
  
  void log(String message) {
    logs.add("[${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}] $message");
    status = message;
    notifyListeners();
  }

  // KẾT NỐI THỰC SỰ QUA SOCKET
  Future<void> connect(String ip) async {
    try {
      log("Đang bắt tay với thiết bị $ip...");
      
      // Mở kết nối TCP tới cổng 5555
      _socket = await RawSocket.connect(ip, 5555, timeout: const Duration(seconds: 5));
      
      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          _handleAdbResponse();
        }
      }, onDone: () => _onDisconnected(), onError: (e) => log("Lỗi kết nối: $e"));

      // Gửi bản tin CNXN (Connect) đầu tiên
      _sendAdbMessage(0x4E584E43, 0x01000000, 0x00100000, "host::iPhone17_Pro\0");
      
    } catch (e) {
      log("Không tìm thấy thiết bị: $e");
    }
  }

  void _handleAdbResponse() {
    final data = _socket?.read(1024);
    if (data == null || data.length < 24) return;
    
    final header = ByteData.sublistView(Uint8List.fromList(data));
    final command = header.getUint32(0, Endian.little);
    
    if (command == 0x48545541) { // Lệnh AUTH từ Android
      log("Thiết bị yêu cầu xác thực. Vui lòng nhấn 'Cho phép' trên màn hình Android!");
      // Gửi Public Key (Trong bản này chúng ta gửi giả lập Pubkey để kích hoạt yêu cầu xác thực)
      _sendAdbMessage(0x48545541, 3, 0, "FakeRSAPubKeyToken\0");
    } else if (command == 0x4E584E43) { // Lệnh CNXN (Thành công)
      isConnected = true;
      log("KẾT NỐI THÀNH CÔNG! Sẵn sàng điều khiển.");
      notifyListeners();
    }
  }

  void executeShell(String name, String cmd) {
    if (!isConnected) return;
    log("Gửi lệnh: $name...");
    _sendAdbMessage(0x4E45504F, 0, 0, "shell:$cmd\0");
  }

  void sendTap(Offset pos, Size screenSize) {
    if (!isConnected) return;
    // Chuyển đổi tọa độ iPhone sang tọa độ Android giả định (1080x2400)
    int ax = ((pos.dx / screenSize.width) * 1080).toInt();
    int ay = ((pos.dy / screenSize.height) * 2400).toInt();
    
    executeShell("Chạm", "input tap $ax $ay");
    
    lastTap = pos;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 200), () {
      lastTap = null;
      notifyListeners();
    });
  }

  void _sendAdbMessage(int cmd, int arg0, int arg1, String payloadStr) {
    final payload = Uint8List.fromList(payloadStr.codeUnits);
    final header = ByteData(24);
    header.setUint32(0, cmd, Endian.little);
    header.setUint32(4, arg0, Endian.little);
    header.setUint32(8, arg1, Endian.little);
    header.setUint32(12, payload.length, Endian.little);
    header.setUint32(16, payload.fold(0, (a, b) => a + b), Endian.little);
    header.setUint32(20, cmd ^ 0xFFFFFFFF, Endian.little);
    
    final full = Uint8List(24 + payload.length);
    full.setRange(0, 24, header.buffer.asUint8List());
    full.setRange(24, 24 + payload.length, payload);
    _socket?.write(full);
  }

  void disconnect() {
    _socket?.close();
    _onDisconnected();
  }

  void _onDisconnected() {
    isConnected = false;
    isRemoteActive = false;
    log("Đã ngắt kết nối.");
    notifyListeners();
  }

  void toggleRemote() {
    isRemoteActive = !isRemoteActive;
    SystemChrome.setPreferredOrientations(isRemoteActive 
      ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] 
      : [DeviceOrientation.portraitUp]);
    notifyListeners();
  }
}

// --- GIAO DIỆN (PREMIUM UI) ---
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
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF020617)), 
      home: const Dashboard()
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final adb = Provider.of<AdbManager>(context);
    final ctrl = TextEditingController(text: "192.168.1.");

    return Scaffold(
      body: Stack(
        children: [
          _blurOrb(const Color(0xFF1E40AF), top: -150, left: -50),
          _blurOrb(const Color(0xFF701A75), bottom: -150, right: -50),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: adb.isRemoteActive 
                ? _buildRemoteView(adb, context) 
                : _buildMainView(adb, ctrl),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView(AdbManager adb, TextEditingController ctrl) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 50),
            Text("ADB PRO", style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
            const Text("DÂY CHUYỀN ĐIỀU KHIỂN NATIVE", style: TextStyle(color: Colors.blueAccent, letterSpacing: 2, fontSize: 8)),
            const SizedBox(height: 60),
            
            // Connection Status
            _connStatus(adb.isConnected),
            const SizedBox(height: 50),

            _glass(
              child: Column(
                children: [
                  TextField(controller: ctrl, style: const TextStyle(fontSize: 18), decoration: const InputDecoration(border: InputBorder.none, icon: Icon(Icons.wifi_tethering, color: Colors.blueAccent), hintText: "Nhập IP Android (vd: 192.168.1.5)")),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 10),
                  if (adb.isConnected)
                    Row(
                      children: [
                        Expanded(child: _btn("OPEN REMOTE", Colors.green, adb.toggleRemote)),
                        const SizedBox(width: 10),
                        Expanded(child: _btn("DISCONNECT", Colors.redAccent.withOpacity(0.7), adb.disconnect)),
                      ],
                    )
                  else
                    _btn("KẾT NỐI THIẾT BỊ", Colors.blueAccent, () => adb.connect(ctrl.text)),
                ],
              ),
            ),

            const SizedBox(height: 30),
            if (adb.isConnected) _buildQuickHub(adb),
            const SizedBox(height: 30),
            _logs(adb),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickHub(AdbManager adb) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("  HÀNH ĐỘNG NHANH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.3,
          children: [
            _card(Icons.upgrade, "UPDATE KDS", Colors.orange, () => adb.executeShell("Update KDS", "sh /data/local/tmp/update.sh")),
            _card(Icons.install_mobile, "CÀI APK", Colors.purpleAccent, () => adb.executeShell("Cài đặt APK", "pm install /sdcard/app.apk")),
            _card(Icons.camera_alt, "SCREENSHOT", Colors.cyanAccent, () => adb.executeShell("Chụp màn hình", "screencap /sdcard/s.png")),
            _card(Icons.power_settings_new, "REBOOT", Colors.redAccent, () => adb.executeShell("Khởi động lại", "reboot")),
          ],
        ),
      ],
    );
  }

  Widget _buildRemoteView(AdbManager adb, BuildContext context) {
    return Row(
      children: [
        Container(
          width: 70, 
          color: Colors.black45,
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () => adb.toggleRemote()), const Icon(Icons.home_outlined), const Icon(Icons.arrow_back_ios_new)]),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (details) => adb.sendTap(details.localPosition, Size(constraints.maxWidth, constraints.maxHeight)),
                child: Container(
                  margin: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Text("TRUYỀN HÌNH ANDROID", style: TextStyle(color: Colors.white12, fontWeight: FontWeight.bold)),
                      if (adb.lastTap != null)
                        Positioned(
                          left: adb.lastTap!.dx - 20, 
                          top: adb.lastTap!.dy - 20, 
                          child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                        ),
                    ],
                  ),
                ),
              );
            }
          ),
        ),
      ],
    );
  }

  // --- Helpers ---
  Widget _blurOrb(Color c, {double? top, double? left, double? bottom, double? right}) => Positioned(top: top, left: left, bottom: bottom, right: right, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100), child: Container(width: 350, height: 350, decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.15)))));
  Widget _connStatus(bool c) => Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c ? Colors.greenAccent : Colors.blueAccent, width: 2)), child: Icon(c ? Icons.link : Icons.link_off, size: 40, color: c ? Colors.greenAccent : Colors.blueAccent));
  Widget _glass({required Widget child}) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)), child: child);
  Widget _btn(String t, Color c, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(15)), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))));
  Widget _card(IconData i, String l, Color c, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 18, color: c), const SizedBox(width: 8), Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))])));
  Widget _logs(AdbManager adb) => Container(height: 100, width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(15)), child: ListView.builder(itemCount: adb.logs.length, itemBuilder: (context, i) => Text(adb.logs[i], style: const TextStyle(fontSize: 9, color: Colors.blueAccent))));
}
