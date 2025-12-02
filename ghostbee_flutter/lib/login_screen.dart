import 'package:flutter/material.dart';
import 'package:ghostbee_flutter/constants.dart';
import 'package:ghostbee_flutter/models/user.dart';
import 'package:http/http.dart' as http; // 1. Import http
import 'dart:convert'; // 2. Import jsonEncode/Decode
import 'main.dart';
import 'register_screen.dart';
import 'socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <<< Import ใหม่

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  // --- ฟังก์ชัน Login แบบเชื่อม Database ---
  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      // เริ่มโหลด
      setState(() {
        _isLoading = true;
      });

      // ดึงค่าจากช่องกรอก
      String username = _usernameController.text.trim();
      String password = _passwordController.text.trim();

      try {
        final response = await http.post(
          Uri.parse('$baseUrl/login'),
          headers: {"Content-Type": "application/json; charset=UTF-8"},
          body: jsonEncode({"username": username, "password": password}),
        );

        // เช็คว่าหน้าจอยังเปิดอยู่ไหม (ป้องกัน error กรณีปิดแอพระหว่างโหลด)
        if (!mounted) return;

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final user = User.fromJson(data['user']);

          // 1. บันทึกสถานะ Login: User ID หรือ Token
          final prefs = await SharedPreferences.getInstance();
          // เราจะบันทึก ID ของผู้ใช้เป็นตัวบ่งชี้ว่าล็อกอินแล้ว
          await prefs.setInt('userId', user.id);
          // ถ้า Server ส่ง Token มาด้วย: await prefs.setString('authToken', data['token']);
          SocketService().initialize(user.id);
          if (!mounted) return;

          // 2. ไปยังหน้าหลัก
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => MainScreen(user: user)),
            (route) => false,
          );
        } else {
          // --- ❌ Login ไม่ผ่าน (รหัสผิด หรือ ไม่พบ User) ---
          setState(() {
            _isLoading = false; // หยุดหมุน
          });

          // อ่านข้อความ Error จาก Server
          final errorData = jsonDecode(response.body);
          String errorMessage = errorData['message'] ?? 'Login failed';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: $errorMessage"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        // --- ❌ Error การเชื่อมต่อ (Server ดับ / เน็ตหลุด) ---
        setState(() {
          _isLoading = false;
        });

        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text("Connection Error"),
                content: Text(
                  "Cannot connect to server.\nCheck if server.js is running.\n\nError: $e",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"),
                  ),
                ],
              ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI ส่วนนี้เหมือนเดิม 100% ครับ แค่เรียกใช้ _handleLogin ตัวใหม่ด้านบน
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.hive,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "GhostBee",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Username
                  TextFormField(
                    controller: _usernameController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: "Phone / Username",
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_isLoading,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),

                  const SizedBox(height: 30),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        disabledBackgroundColor: Colors.amber.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child:
                          _isLoading
                              ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text(
                                "Log In",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed:
                            _isLoading
                                ? null
                                : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => const RegisterScreen(),
                                  ),
                                ),
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
