// main.dart

import 'dart:convert';
import './config_service.dart';
import './constants.dart';
import 'package:flutter/material.dart';
import 'package:ghostbee_flutter/board_screen.dart';
import 'package:ghostbee_flutter/chat_screen.dart';
import 'package:ghostbee_flutter/club_list_screen.dart';
import 'package:ghostbee_flutter/models/user.dart';
import 'package:ghostbee_flutter/profile_screen.dart';
import 'package:ghostbee_flutter/socket_service.dart';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'login_screen.dart'; // หน้า Login (หน้าแรกสุด)
import 'club_room_screen.dart'; // หน้าห้อง Club
import 'package:shared_preferences/shared_preferences.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. โหลด Config ที่บันทึกไว้ในเครื่อง (Saved Config)
  await ConfigService.loadSavedConfig(); 

  // 2. ลองดึง Config ล่าสุดจาก GitHub
  final remoteConfig = await ConfigService.fetchLatestConfig();

  if (remoteConfig != null) {
    final remoteUrl = remoteConfig["api_base_url"] as String;
    final remoteVersion = remoteConfig["config_version"] ?? 0;

    // 3. ถ้า Config จาก Remote ใหม่กว่า Config ที่แอปฯ โหลดมา (จาก SharedPrefs/Default 0)
    if (remoteVersion > ConfigService.currentConfigVersion) {
      // 4. อัปเดตไปใช้ Config ใหม่ทันที (เพื่อใช้ในการเชื่อมต่อครั้งแรก)
      await ConfigService.setBaseUrl(remoteUrl, remoteVersion);
    } 
  }
  
  // 5. อัปเดต baseUrl ให้ทั้งระบบ
  AppConstants.baseUrl = ConfigService.baseUrl;

  runApp(const BeeTalkApp());
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  Widget _initialScreen = const Center(
    child: CircularProgressIndicator(color: Colors.amber),
  );

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // ✨ NEW: เมธอดสำหรับแสดง Pop-up แจ้งเตือน
  void _showUpdatePopup(BuildContext context, Map<String, dynamic> latestConfig) {
    final newUrl = latestConfig["api_base_url"] as String;
    final newVersion = latestConfig.containsKey("config_version") 
        ? latestConfig["config_version"].toString() 
        : "N/A";

    showDialog(
      context: context,
      barrierDismissible: false, // บังคับให้เลือกปุ่ม
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.amber),
            SizedBox(width: 10),
            Text("อัปเดตเซิร์ฟเวอร์ด่วน!"), 
          ],
        ),
        content: Text(
          "เราตรวจพบ Config เวอร์ชันใหม่ (v$newVersion) ซึ่งแก้ไขปัญหาการเชื่อมต่อ\nกรุณากด 'อัปเดต' เพื่อเชื่อมต่อเซิร์ฟเวอร์ใหม่และใช้งานต่อ",
        ),
        actions: [
          // ปุ่ม "ข้าม"
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // ถ้าผู้ใช้เลือกข้าม ให้นำไปหน้า Login 
              if (mounted) {
                setState(() => _initialScreen = const LoginScreen());
              }
            },
            child: const Text("ข้าม", style: TextStyle(color: Colors.grey)),
          ),
          
          // ปุ่ม "อัปเดต"
          ElevatedButton(
            onPressed: () async { // 🌟 ต้องเป็น async เพื่อ await setBaseUrl
              // 1. เซ็ตค่า Base URL ใหม่ และบันทึกใน SharedPrefs
              final int versionInt = latestConfig["config_version"] ?? ConfigService.currentConfigVersion;
              await ConfigService.setBaseUrl(newUrl, versionInt); 
              
              Navigator.pop(ctx);
              
              // 2. ลองเช็คสถานะการล็อกอินซ้ำอีกครั้งด้วย URL ใหม่
              _checkLoginStatus(); 
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("อัปเดต", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (!mounted) return;
    
    // ⚠️ Safety Check: หาก BaseUrl ยังว่าง (กรณี Config Load ครั้งแรกไม่สำเร็จ)
    // ให้พยายามโหลด Config ล่าสุดอีกครั้ง
    if (AppConstants.baseUrl.isEmpty) {
        final latestConfig = await ConfigService.fetchLatestConfig();
        if (latestConfig != null) {
            final initialUrl = latestConfig["api_base_url"] as String;
            final initialVersion = latestConfig["config_version"] ?? 0;
            // ใช้ setBaseUrl เพื่อบันทึกค่าแรกที่ดึงมาได้
            await ConfigService.setBaseUrl(initialUrl, initialVersion);
        }
    }


    if (userId != null) {
      // 1. ถ้ามี ID (เคย Login แล้ว) -> ดึงข้อมูล User ที่สมบูรณ์
      try {
        final response = await http.get(
          Uri.parse('${AppConstants.baseUrl}/user/$userId'),
        ); // <<< เรียก API ใหม่

        if (response.statusCode == 200) {
          // ดึงข้อมูล User และสร้าง User Object ที่สมบูรณ์
          final data = jsonDecode(response.body);
          final user = User.fromJson(data['user']);
          SocketService().initialize(user.id);
          if (mounted) {
            setState(() {
              _initialScreen = MainScreen(
                user: user,
              ); // ไป MainScreen พร้อม User Object จริง
            });
          }
        } else {
          // 2. ถ้าดึงข้อมูล User ไม่สำเร็จ (เช่น User ถูกลบ) -> กลับไป Login
          await prefs.remove('userId'); // ล้างสถานะ
          if (mounted) {
            setState(() {
              _initialScreen = const LoginScreen();
            });
          }
        }
      } catch (e) {
        // 3. Connection Error/Server Down -> ลองดึง Config ล่าสุดมาเปรียบเทียบ
        print("Error during auto-login fetch: $e. Checking for config update...");
        
        // 🌟 Fix: ดึง Config ล่าสุด
        final latestConfig = await ConfigService.fetchLatestConfig();
        
        if (latestConfig != null) {
          final int newVersion = latestConfig["config_version"] ?? 0;
          
          // 🌟 Fix: เปรียบเทียบ Remote Version กับ Config ที่บันทึกไว้ (currentConfigVersion)
          if (newVersion > ConfigService.currentConfigVersion) {
            print("Config Update Found: Remote v$newVersion > Local v${ConfigService.currentConfigVersion}");
            if (mounted) {
              _showUpdatePopup(context, latestConfig);
            }
            return; // หยุดการทำงานชั่วคราว รอผู้ใช้เลือกใน Pop-up
          }
        }
        
        // ถ้าไม่มี Config ใหม่ หรือโหลด Config ไม่ได้ ให้ไปหน้า Login ปกติ
        if (mounted) {
          setState(() {
            _initialScreen = const LoginScreen();
          });
        }
      }
    } else {
      // 4. ถ้าไม่มี ID (ยังไม่เคย Login) -> ไป LoginScreen
      setState(() {
        _initialScreen = const LoginScreen();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _initialScreen;
  }
}

class BeeTalkApp extends StatelessWidget {
  const BeeTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BeeTalk Clone',
      theme: ThemeData(
        primarySwatch: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFC107),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      // เริ่มต้นที่หน้า Login เสมอ เพื่อให้ User Login ก่อนเข้าใช้งาน
      home: const AuthWrapper(),
    );
  }
}

// ---------------------------------------------------------
// MainScreen: หน้าหลักที่มี Bottom Navigation (โค้ดเดิม)
// ---------------------------------------------------------
class MainScreen extends StatefulWidget {
  final User user; 

  const MainScreen({super.key, required this.user});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1; 

  late List<Widget> _pages;
  final List<String> _titles = ["Chats", "Board", "Clubs", "Me"];

  @override
  void initState() {
    super.initState();
    _pages = [
      ChatPlaceholder(user: widget.user),
      BoardScreen(currentUser: widget.user),
      ClubListScreen(currentUser: widget.user),
      ProfileScreen(user: widget.user), 
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book_rounded),
            label: 'Board',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.group_work), label: 'Clubs'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Me'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}

// ---------------------------------------------------------
// 1. Chat Tab (Mockup) (โค้ดเดิม)
// ---------------------------------------------------------
class ChatPlaceholder extends StatefulWidget {
  final User user; 
  const ChatPlaceholder({super.key, required this.user});

  @override
  State<ChatPlaceholder> createState() => _ChatPlaceholderState();
}

class _ChatPlaceholderState extends State<ChatPlaceholder> {
  List<dynamic> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/friends/${widget.user.id}'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _friends = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching friends: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_friends.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sentiment_dissatisfied, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text("No friends yet.", style: TextStyle(color: Colors.grey)),
            Text(
              "Go to 'New Friends' in Me tab to accept requests.",
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _friends.length,
      itemBuilder: (ctx, i) {
        final friend = _friends[i];
        int unread = friend['unread_count'] ?? 0;
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black12)),
          ),
          child: ListTile(
            tileColor: Colors.white,
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor:
                      friend['gender'] == 'male'
                          ? Colors.blue[100]
                          : Colors.pink[100],
                  backgroundImage:
                      friend['image'] != null &&
                              friend['image'].toString().startsWith('http')
                          ? NetworkImage(friend['image'])
                          : null,
                  child:
                      (friend['image'] == null ||
                              !friend['image'].toString().startsWith('http'))
                          ? Icon(
                            Icons.person,
                            color:
                                friend['gender'] == 'male'
                                    ? Colors.blue
                                    : Colors.pink,
                          )
                          : null,
                ),
              ],
            ),

            title: Text(
              friend['display_name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            subtitle: const Text(
              "Tap to chat",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            // จุดแดงแจ้งเตือน
            trailing:
                unread > 0
                    ? Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unread.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                    : const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),

            onTap: () async {
              // กดแล้วไปหน้า ChatScreen
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          ChatScreen(currentUser: widget.user, friend: friend),
                ),
              );

              // 🔄 เมื่อกลับออกมาจากหน้าแชท ให้โหลดข้อมูลใหม่ (เพื่อให้เลขแดงๆ หายไป)
              _fetchFriends();
            },
          ),
        );
      },
    );
  }
}