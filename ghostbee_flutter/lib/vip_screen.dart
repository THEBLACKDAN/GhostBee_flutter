import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import './models/user.dart';
import 'constants.dart';

class VipScreen extends StatefulWidget {
  final User currentUser;
  const VipScreen({super.key, required this.currentUser});

  @override
  State<VipScreen> createState() => _VipScreenState();
}

class _VipScreenState extends State<VipScreen> {
  bool _isLoading = false;

  // ฟังก์ชันคำนวณวันหมดอายุเป็น String สวยๆ
  String _getExpireDateString() {
    // เนื่องจาก User Model เราอาจจะยังไม่ได้ map field 'vip_expire_at'
    // ในที่นี้เราจะดูสถานะคร่าวๆ หรือถ้าคุณอัปเดต Model แล้วก็ดึงมาโชว์ได้
    if (widget.currentUser.isVip) {
      return "สถานะ: เป็น VIP อยู่";
    }
    return "สถานะ: สมาชิกทั่วไป";
  }

  Future<void> _buyVip(int days, int cost) async {
    // Client Check
    if (widget.currentUser.coinBalance < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Coin ไม่พอ! กรุณาเติมเงินก่อน")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/buy-vip'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.currentUser.id,
          "days": days,
          "cost": cost,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = data['user'];

        setState(() {
          // อัปเดตข้อมูล User ในแอปทันที
          widget.currentUser.coinBalance = userData['coin_balance'];
          // เราต้องมั่นใจว่า Model User รองรับการ set isVip (ถ้าเป็น final ต้องแก้ model นิดหน่อย หรือใช้วิธี force update)
          // สมมติว่า User model มี isVip เป็น final แต่เราแก้เฉพาะหน้าไปก่อน
          // ทางที่ดีที่สุดคือ ไปแก้ models/user.dart ให้ field ไม่เป็น final หรือมี method copyWith

          // *หมายเหตุ: เพื่อให้ง่าย ผมจะถือว่าเรา Reload หน้า Profile เอา
        });

        if (!mounted) return;

        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text("👑 สมัคร VIP สำเร็จ!"),
                content: Text(
                  "คุณเป็น VIP แล้ว เป็นเวลา $days วัน\nเหลือเงิน: ${userData['coin_balance']} Coins",
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx); // ปิด Dialog
                      Navigator.pop(
                        context,
                        true,
                      ); // ปิดหน้านี้ กลับไปหน้า Profile พร้อมค่า true
                    },
                    child: const Text("ตกลง"),
                  ),
                ],
              ),
        );
      } else {
        final err = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['message'] ?? "เกิดข้อผิดพลาด")),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Error connection")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // พื้นหลังสีเข้มดูพรีเมียม
      appBar: AppBar(
        title: const Text("VIP Membership"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Header
              const Icon(
                Icons.workspace_premium,
                size: 80,
                color: Colors.amber,
              ),
              const SizedBox(height: 10),
              const Text(
                "Upgrade to VIP",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "โพสต์ได้ไม่จำกัด • ชื่อสีทอง • ฟีเจอร์พิเศษ",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 30),

              // Coin Balance
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Your Balance: ${widget.currentUser.coinBalance}",
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Package 1: 7 Days
              _buildVipCard(
                title: "Weekly VIP",
                days: 7,
                price: 3000,
                color: Colors.blueAccent,
                isBestValue: false,
              ),

              const SizedBox(height: 20),

              // Package 2: 30 Days
              _buildVipCard(
                title: "Monthly VIP",
                days: 30,
                price: 10000, // ราคา 30 ตามที่คุณขอ
                color: Colors.purpleAccent,
                isBestValue: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVipCard({
    required String title,
    required int days,
    required int price,
    required Color color,
    required bool isBestValue,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _buyVip(days, price),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.8), color.withOpacity(0.4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBestValue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(bottom: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        "BEST VALUE",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "$days Days Access",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  "$price",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text("Coins", style: TextStyle(color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
