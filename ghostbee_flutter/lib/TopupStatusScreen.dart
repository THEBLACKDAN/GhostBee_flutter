// TopupStatusScreen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user.dart';
import '../constants.dart';

class TopupStatusScreen extends StatefulWidget {
  final int historyId;
  final User currentUser;

  TopupStatusScreen({required this.historyId, required this.currentUser});

  @override
  State<TopupStatusScreen> createState() => _TopupStatusScreenState();
}

class _TopupStatusScreenState extends State<TopupStatusScreen> {
  String status = 'pending';
  String message = 'กำลังตรวจสอบสลิป...';
  int coinsAdded = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // เริ่มตรวจสอบสถานะทุกๆ 3 วินาที
    timer = Timer.periodic(Duration(seconds: 3), (Timer t) => _checkStatus());
    _checkStatus(); // ตรวจสอบทันทีที่เข้าหน้าจอ
  }

  @override
  void dispose() {
    timer?.cancel(); // อย่าลืมยกเลิก Timer เมื่อออกจากหน้าจอ
    super.dispose();
  }

  Future<void> _checkStatus() async {
    // ไม่ต้องตรวจสอบต่อ ถ้าสำเร็จหรือล้มเหลวแล้ว
    if (status != 'pending') {
      timer?.cancel();
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/payment/status/${widget.historyId}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          status = data['status'];
          coinsAdded = data['coins_added'];
          message = data['message'] ?? 'ตรวจสอบสำเร็จ';
        });

        // หากสำเร็จหรือล้มเหลวแล้ว ให้อัปเดตข้อมูลผู้ใช้และปิด Timer
        if (status != 'pending') {
          timer?.cancel();
          if (status == 'success') {
            // ⚠️ ต้องมีฟังก์ชันเพื่ออัปเดตข้อมูลผู้ใช้ในแอปจริง
            // เช่น: widget.currentUser.coin_balance += coinsAdded;
          }
        }
      } else {
        setState(() {
          message = 'เกิดข้อผิดพลาดในการดึงสถานะ';
          timer?.cancel();
        });
      }
    } catch (e) {
      print("Status Check Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // กำหนดสีและไอคอนตามสถานะ
    Color displayColor = Colors.orange;
    IconData displayIcon = Icons.hourglass_top;

    if (status == 'success') {
      displayColor = Colors.green;
      displayIcon = Icons.check_circle;
    } else if (status == 'failed') {
      displayColor = Colors.red;
      displayIcon = Icons.cancel;
    }

    return Scaffold(
      appBar: AppBar(title: Text("สถานะการเติมเงิน")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(displayIcon, size: 80, color: displayColor),
              SizedBox(height: 20),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: displayColor,
                ),
              ),
              SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              if (status == 'success') ...[
                SizedBox(height: 20),
                Text(
                  "คุณได้รับ ${coinsAdded} Coins!",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
              SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(
                    context,
                    (route) => route.isFirst,
                  ); // กลับไปหน้าแรก
                },
                child: Text("กลับหน้าหลัก"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
