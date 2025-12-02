import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import './models/user.dart';
import '../constants.dart';

class FriendRequestsScreen extends StatefulWidget {
  final User currentUser;
  const FriendRequestsScreen({super.key, required this.currentUser});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  // ดึงข้อมูลคำขอ
  Future<void> _fetchRequests() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConstants.baseUrl}/friend-requests/${widget.currentUser.id}',
        ),
      );
      if (response.statusCode == 200) {
        setState(() {
          _requests = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  // ฟังก์ชันตอบรับ (action = 'accepted' หรือ 'rejected')
  Future<void> _respond(int requestId, String action) async {
    try {
      await http.put(
        Uri.parse('${AppConstants.baseUrl}/respond-request'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"request_id": requestId, "action": action}),
      );

      // อัปเดตหน้าจอโดยลบรายการนั้นออกทันที
      setState(() {
        _requests.removeWhere((item) => item['request_id'] == requestId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'accepted' ? "Friend Added!" : "Request Removed",
          ),
          backgroundColor: action == 'accepted' ? Colors.green : Colors.grey,
        ),
      );
    } catch (e) {
      print("Error responding: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Friends")),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _requests.isEmpty
              ? const Center(
                child: Text(
                  "No new requests",
                  style: TextStyle(color: Colors.grey),
                ),
              )
              : ListView.builder(
                itemCount: _requests.length,
                itemBuilder: (context, index) {
                  final req = _requests[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 25,
                            backgroundColor:
                                req['gender'] == 'male'
                                    ? Colors.blue[100]
                                    : Colors.pink[100],
                            child: Icon(
                              Icons.person,
                              color:
                                  req['gender'] == 'male'
                                      ? Colors.blue
                                      : Colors.pink,
                            ),
                          ),
                          const SizedBox(width: 15),

                          // Name
                          Expanded(
                            child: Text(
                              req['display_name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),

                          // Buttons
                          Row(
                            children: [
                              // ปุ่มปฏิเสธ
                              ElevatedButton(
                                onPressed:
                                    () =>
                                        _respond(req['request_id'], 'rejected'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[300],
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                child: const Text("Delete"),
                              ),
                              const SizedBox(width: 8),
                              // ปุ่มยอมรับ
                              ElevatedButton(
                                onPressed:
                                    () =>
                                        _respond(req['request_id'], 'accepted'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                child: const Text("Confirm"),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
