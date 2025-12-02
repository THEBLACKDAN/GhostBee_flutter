import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import './models/user.dart';
import 'constants.dart';

class TopUpScreen extends StatefulWidget {
  final User currentUser;
  const TopUpScreen({super.key, required this.currentUser});

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  bool _isLoading = false;

  // รายการแพ็กเกจสินค้า (จำลอง)
  final List<Map<String, dynamic>> _coinPackages = [
    {"coins": 600, "price": 39, "color": Colors.green},
    {"coins": 1500, "price": 59, "color": Colors.blue},
    {"coins": 3000, "price": 149, "color": Colors.purple},
    {"coins": 4500, "price": 249, "color": Colors.orange},
    {"coins": 6000, "price": 499, "color": Colors.red},
    {"coins": 10000, "price": 599, "color": Colors.black87},
  ];

  Future<void> _buyCoins(int amount, int price) async {
    setState(() => _isLoading = true);

    try {
      // 1. ยิง API ไปเติมเงิน
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/topup'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.currentUser.id, "amount": amount}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 2. อัปเดตเงินในแอปทันที
        setState(() {
          widget.currentUser.coinBalance = data['new_balance'];
        });

        if (!mounted) return;

        // 3. แสดง Success Dialog
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text("🎉 เติมเงินสำเร็จ!"),
                content: Text(
                  "คุณได้รับ $amount Coins แล้ว\nยอดรวม: ${widget.currentUser.coinBalance}",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"),
                  ),
                ],
              ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("เกิดข้อผิดพลาดในการเติมเงิน")),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("เชื่อมต่อ Server ไม่ได้")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Top Up Coins"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ส่วนหัวแสดงยอดเงินปัจจุบัน
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.amber[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.monetization_on,
                  size: 40,
                  color: Colors.amber,
                ),
                const SizedBox(width: 10),
                Column(
                  children: [
                    const Text(
                      "Current Balance",
                      style: TextStyle(color: Colors.grey),
                    ),
                    Text(
                      "${widget.currentUser.coinBalance}",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ตารางแพ็กเกจสินค้า
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                      padding: const EdgeInsets.all(15),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, // 2 คอลัมน์
                            childAspectRatio: 1.4, // สัดส่วนกว้าง/สูง
                            crossAxisSpacing: 15,
                            mainAxisSpacing: 15,
                          ),
                      itemCount: _coinPackages.length,
                      itemBuilder: (context, index) {
                        final pkg = _coinPackages[index];
                        return GestureDetector(
                          onTap: () => _buyCoins(pkg['coins'], pkg['price']),
                          child: Container(
                            decoration: BoxDecoration(
                              color: pkg['color'].withOpacity(0.1),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: pkg['color'], width: 2),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.monetization_on,
                                  color: pkg['color'],
                                  size: 30,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "+${pkg['coins']} Coins",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: pkg['color'],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "THB ${pkg['price']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
