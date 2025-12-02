// lib/club_list_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // สำหรับจัดรูปแบบเวลา
import 'constants.dart';
import './models/user.dart';
import 'club_room_screen.dart'; 

// ---------------------------------------------------------
// ClubListScreen (แทน ClubPlaceholder เดิม)
// หน้าสำหรับแสดงรายการ Club และปุ่มสร้าง Club
// ---------------------------------------------------------
class ClubListScreen extends StatefulWidget {
  final User currentUser; 
  const ClubListScreen({super.key, required this.currentUser});

  @override
  State<ClubListScreen> createState() => _ClubListScreenState();
}

class _ClubListScreenState extends State<ClubListScreen> {
  List<dynamic> _clubs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchClubs(); // ดึงข้อมูล Club ตั้งแต่ต้น
  }
  
  // ฟังก์ชันดึง Club ทั้งหมดจาก Server
  Future<void> _fetchClubs() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/clubs'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _clubs = data['clubs'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showSnackbar("Failed to load clubs: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackbar("Network Error fetching clubs: $e", isError: true);
    }
  }

  // ฟังก์ชันสร้าง Club ใหม่
  Future<void> _createClub(String clubName) async {
    Navigator.pop(context); // ปิด dialog
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/clubs'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'clubName': clubName,
          'ownerId': widget.currentUser.id, // ส่ง ID ผู้สร้าง
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        final newClub = data['club'];
        _showSnackbar("Club '${newClub['name']}' created!", isError: false);
        
        await _fetchClubs(); // อัปเดตรายการ Club
        
        _navigateToClubRoom(newClub); // พาเข้าห้องที่เพิ่งสร้างทันที

      } else {
        _showSnackbar("Failed to create club: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      _showSnackbar("Network Error creating club: $e", isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Dialog สำหรับกรอกชื่อ Club
  void _showCreateClubDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create New Club"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter club name"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _createClub(controller.text.trim());
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }
  
  // Helper: Navigation
  void _navigateToClubRoom(Map<String, dynamic> club) {
     Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClubRoomScreen(
          currentUser: widget.currentUser,
          clubId: club['id'],
          clubName: club['name'],
          
          // <<< เพิ่ม ARGUMENTS ที่ขาดหายไป 2 ตัวนี้ >>>
          ownerId: club['ownerId'], // ⚠️ Club owner ID
          onClubEnd: _fetchClubs, // ⚠️ Callback function (_fetchClubs)
        ),
      ),
    );
  }

  void _showSnackbar(String message, {required bool isError}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }
  
  // ----------------------------------------------------
  // BUILD METHOD
  // ----------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }
    
    // ถ้าไม่มี Club ให้แสดงข้อความ
    if (_clubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("No active clubs. Create one!", style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _showCreateClubDialog,
              icon: const Icon(Icons.add_circle, color: Colors.white),
              label: const Text("Create Club"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            ),
          ],
        ),
      );
    }
    
    // ถ้ามี Club
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchClubs,
        child: GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: _clubs.length,
          itemBuilder: (ctx, i) {
            final club = _clubs[i];
            
            // Helper: คำนวณเวลาที่เหลือ
            final expiryTime = DateTime.parse(club['expires_at']);
            final timeRemaining = expiryTime.difference(DateTime.now());
            final minutes = timeRemaining.inMinutes.remainder(60).toString().padLeft(2, '0');
            final seconds = timeRemaining.inSeconds.remainder(60).toString().padLeft(2, '0');
            final timeString = timeRemaining.inSeconds > 0 ? "$minutes:$seconds" : "Closing...";
            
            return GestureDetector(
              onTap: () => _navigateToClubRoom(club),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Image.network(
                          "https://i.pravatar.cc/150?img=${club['id'] % 25}", 
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            club['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Time Left: $timeString",
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.group,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${club['members']} Members",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      // Floating Action Button สำหรับสร้าง Club
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateClubDialog,
        backgroundColor: Colors.amber,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}