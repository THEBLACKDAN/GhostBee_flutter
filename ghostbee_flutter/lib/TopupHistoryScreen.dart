// TopupHistoryScreen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/user.dart'; // ต้องแน่ใจว่าไฟล์นี้เข้าถึงได้
import '../constants.dart'; // ต้องแน่ใจว่าไฟล์นี้เข้าถึงได้

class TopupHistoryScreen extends StatefulWidget {
  final User currentUser;
  TopupHistoryScreen({required this.currentUser});

  @override
  State<TopupHistoryScreen> createState() => _TopupHistoryScreenState();
}

class _TopupHistoryScreenState extends State<TopupHistoryScreen> {
  List<dynamic> historyList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  // -----------------------------
  // โหลดประวัติจาก API /payment/history/:userId
  // -----------------------------
  Future<void> _fetchHistory() async {
    // ⚠️ ควรเพิ่ม if (!mounted) return; หากมีการใช้ async/await
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse(
          "${AppConstants.baseUrl}/payment/history/${widget.currentUser.id}",
        ),
      );

      if (response.statusCode == 200) {
        setState(() {
          historyList = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        print("Failed to load history: ${response.statusCode}");
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print("History load error: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  // Helper สำหรับแสดงสีตามสถานะ
  Color _getStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'reserved':
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ประวัติการเติมเงิน"), // ใช้ const
        backgroundColor: Colors.deepPurple,
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator()) // ใช้ const
              : historyList.isEmpty
              ? const Center(
                child: Text("ไม่พบประวัติการเติมเงิน"),
              ) // ใช้ const
              : ListView.builder(
                padding: const EdgeInsets.all(10), // ใช้ const
                itemCount: historyList.length,
                itemBuilder: (context, index) {
                  final item = historyList[index];
                  final status = item['status'] ?? 'reserved';

                  // 🌟 Optimization: คำนวณค่าทั้งหมดที่จำเป็นไว้ข้างนอก
                  final date = DateFormat(
                    'dd MMM yyyy HH:mm',
                  ).format(DateTime.parse(item['created_at']));
                  final double amountToDisplay =
                      double.tryParse(item['amount'].toString()) ?? 0.0;
                  final int coinsAdded =
                      int.tryParse(item['coins_added'].toString()) ?? 0;
                  final Color statusColor = _getStatusColor(status);

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 8,
                    ), // ใช้ const
                    elevation: 3,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor, // ใช้ตัวแปร
                        child: Icon(
                          status == 'success' ? Icons.check : Icons.close,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        "รายการโอน: ${amountToDisplay.toStringAsFixed(2)} บาท",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ), // ใช้ const
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "สถานะ: ${status.toUpperCase()}",
                            style: TextStyle(color: statusColor),
                          ), // ใช้ตัวแปร
                          if (status == 'success')
                            Text(
                              "ได้รับ: $coinsAdded Coins",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ), // ใช้ const
                          if (item['message'] != null)
                            Text(
                              "ข้อความ: ${item['message']}",
                              style: const TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ), // ใช้ const
                          Text(
                            "วันที่: $date",
                            style: const TextStyle(fontSize: 12),
                          ), // ใช้ const
                        ],
                      ),
                      trailing:
                          status == 'pending'
                              ? const Icon(
                                Icons.refresh,
                                color: Colors.orange,
                              ) // ใช้ const
                              : null,
                      onTap: () {
                        // Optional: เพิ่มหน้าจอรายละเอียด
                      },
                    ),
                  );
                },
              ),
    );
  }
}
