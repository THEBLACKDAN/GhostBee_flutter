import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // Import http
import 'dart:convert'; // Import เพื่อใช้ jsonEncode
import 'main.dart'; 
import 'constants.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _usernameController = TextEditingController(); // ใช้รับเบอร์โทร
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  String _selectedGender = 'male';
  bool _isLoading = false; // สถานะโหลด

  // ฟังก์ชันยิง API
  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // ⚠️ สำคัญมาก: IP Address สำหรับ Emulator
      // - Android Emulator ใช้: 'http://10.0.2.2:3000/register'
      // - iOS Simulator ใช้: 'http://localhost:3000/register'
      // - เครื่องจริง: ต้องใช้ IP ของเครื่องคอมฯ เช่น 'http://192.168.1.50:3000/register'
      
      // const String apiUrl = 'http://192.168.101.89:3000/register'; 

      try {
        final response = await http.post(
          Uri.parse('$baseUrl/register'),
          headers: {"Content-Type": "application/json; charset=UTF-8"},
          body: jsonEncode({
            "username": _usernameController.text.trim(),
            "password": _passwordController.text.trim(),
            "display_name": _nameController.text.trim(),
            "gender": _selectedGender,
          }),
        );

        if (!mounted) return;

        // --- แก้ไขตรงนี้ครับ ---
        if (response.statusCode == 201) {
          
          // แสดง Dialog แจ้งเตือนว่า "สมัครเสร็จแล้วนะ"
          showDialog(
            context: context,
            barrierDismissible: false, // บังคับให้กดปุ่ม OK เท่านั้นถึงจะปิด
            builder: (ctx) => AlertDialog(
              title: const Text("สมัครสมาชิกสำเร็จ"),
              content: const Text("สมัครสมาชิกสำเร็จ.\nโปรดเข้าสู่ระบบด้วยชื่อผู้ใช้และรหัสผ่านที่สมัคร."),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx); // 1. ปิด Dialog
                    Navigator.pop(context); // 2. ปิดหน้า Register (จะกลับไปหน้า Login ที่เปิดรออยู่ข้างหลัง)
                  },
                  child: const Text("ไปยังหน้า Login", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );

        } else if (response.statusCode == 409) {
          // Username ซ้ำ
          _showErrorDialog("มีชื่อผู้ใช้งานหรือเบอร์โทรนี้ในระบบแล้ว");
        } else {
          // Error อื่นๆ
          _showErrorDialog("สมัครสมาชิกล้มเหลว: ${response.body}");
        }
        // -----------------------

      } catch (e) {
        _showErrorDialog("Connection Error: $e");
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign Up")),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ... ส่วนรูปภาพ Profile (เหมือนเดิม) ...
              const CircleAvatar(radius: 40, backgroundColor: Colors.amber, child: Icon(Icons.person, color: Colors.white)),
              const SizedBox(height: 20),

              // Inputs
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Display Name", border: OutlineInputBorder(), prefixIcon: Icon(Icons.face)),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _usernameController,
                keyboardType: TextInputType.phone, // ใช้ Phone หรือ Text ก็ได้
                decoration: const InputDecoration(labelText: "Phone / Username", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                validator: (v) => v!.length < 4 ? 'Min 4 chars' : null,
              ),
              const SizedBox(height: 20),

              // Gender Selector (เหมือนเดิม)
              Row(
                children: [
                  _buildGenderBtn("Male", "male", Colors.blue, Icons.male),
                  const SizedBox(width: 16),
                  _buildGenderBtn("Female", "female", Colors.pink, Icons.female),
                ],
              ),
              const SizedBox(height: 30),

              // Register Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Sign Up", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget ย่อยสำหรับปุ่มเลือกเพศ
  Widget _buildGenderBtn(String label, String val, Color color, IconData icon) {
    bool isSelected = _selectedGender == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedGender = val),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.grey[100],
            border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}