import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ghostbee_flutter/TopupHistoryScreen.dart';
import 'package:ghostbee_flutter/topup_packages_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // 🆕 เพิ่ม import Intl สำหรับจัดการวันที่
import './models/user.dart';
import 'constants.dart';
import 'login_screen.dart';
import 'friend_requests_screen.dart';
import 'topup_screen.dart';
import 'vip_screen.dart';
import 'leaderboard_screen.dart';

class ProfileScreen extends StatefulWidget {
  final User user;

  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _pendingRequests = 0;
  bool _isLoadingRequests = true;

  int _postCount = 0;
  int _friendsCount = 0;
  bool _isLoadingStats = true;

  String _userBio = '';

  String _joinedDate = 'N/A'; // 🆕 ตัวแปรสำหรับเก็บวันที่สมัคร

  @override
  void initState() {
    super.initState();
    _fetchFriendRequestsCount();
    _fetchUserStats();
  }

  // --- Logic การเลือกรูปภาพ (VIP Feature) ---
  String _getAvatarUrl() {
    // 1. URL รูปสุ่ม (Default)
    String randomAvatar =
        "https://i.pravatar.cc/150?img=${widget.user.id + 10}";

    // 2. ถ้าเป็น VIP และมีรูป Custom -> ใช้รูป Custom
    if (widget.user.isVip &&
        widget.user.image.isNotEmpty &&
        widget.user.image.startsWith('http')) {
      return widget.user.image;
    }

    // 3. ถ้าไม่เป็น VIP หรือไม่มีรูป -> กลับไปใช้รูปสุ่ม
    return randomAvatar;
  }

  Future<void> _fetchFriendRequestsCount() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/friend-requests/${widget.user.id}'),
      );
      if (mounted && response.statusCode == 200) {
        final List<dynamic> requests = jsonDecode(response.body);
        setState(() {
          _pendingRequests = requests.length;
          _isLoadingRequests = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _fetchUserStats() async {
    try {
      // API call 1: Get Post/Friend Stats
      final responseStats = await http.get(
        Uri.parse('${AppConstants.baseUrl}/user/stats/${widget.user.id}'),
      );
      // API call 2: Get User Details (for coin, VIP, display_name, created_at)
      final responseUser = await http.get(
        Uri.parse('${AppConstants.baseUrl}/user/${widget.user.id}'),
      );

      if (mounted) {
        setState(() {
          if (responseStats.statusCode == 200) {
            final statsData = jsonDecode(responseStats.body);
            // ⚠️ แก้ไข: ต้องใช้ชื่อคีย์ที่ API endpoint นี้ส่งมาจริง (สมมติว่าเป็น 'posts' และ 'friends')
            _postCount = statsData['posts'] ?? 0;
            _friendsCount = statsData['friends'] ?? 0;
          }

          if (responseUser.statusCode == 200) {
            final data = jsonDecode(responseUser.body);
            final userData =
                data is Map && data.containsKey('user') ? data['user'] : data;

            // อัปเดตข้อมูลเหรียญและ VIP
            widget.user.coinBalance =
                userData['coin_balance'] ?? widget.user.coinBalance;
            widget.user.isVip =
                (userData['is_vip'] == 1 || userData['is_vip'] == true);

            // อัปเดตชื่อและรูป
            widget.user.displayName =
                userData['display_name'] ?? widget.user.displayName;
            widget.user.image = userData['image'] ?? widget.user.image;

            _userBio = userData['bio'] ?? '';

            // 🆕 อัปเดตวันที่สมัคร (สมมติว่า API ส่ง created_at มา)
            if (userData['created_at'] != null) {
              try {
                final dateTime = DateTime.parse(userData['created_at']);
                _joinedDate = DateFormat('dd MMM yyyy').format(dateTime);
              } catch (e) {
                _joinedDate = 'Invalid Date';
              }
            }
          }
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  // --- Dialog แก้ไขโปรไฟล์ ---
  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: widget.user.displayName);
    final imageController = TextEditingController(
      text:
          (widget.user.isVip && widget.user.image.startsWith('http'))
              ? widget.user.image
              : "",
    );
    // 🌟 Controller สำหรับ Bio
    final bioController = TextEditingController(text: _userBio); 

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text(
              "แก้ไขโปรไฟล์ส่วนตัว", // ✨ หัวข้อภาษาไทย
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            // 🌟 ใช้ SingleChildScrollView เพื่อป้องกัน Overflow
            content: SingleChildScrollView( 
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. แก้ไขชื่อ (Display Name)
                  const Text("ชื่อที่แสดง", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: "ชื่อแสดงตัวตนของคุณ",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 🌟 NEW: ช่องแก้ไข Bio
                  const Text(
                    "แนะนำตัว (Bio)",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  TextField(
                    controller: bioController,
                    maxLength: 500, // จำกัด 500 ตัวอักษร
                    maxLines: 4,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: "สูงสุด 500 ตัวอักษร",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. แก้ไขรูป (VIP Only)
                  Row(
                    children: [
                      const Text(
                        "ลิงก์รูปโปรไฟล์ (VIP Exclusive)", // ✨ ข้อความภาษาไทย
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      if (widget.user.isVip)
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                    ],
                  ),
                  TextField(
                    controller: imageController,
                    enabled: widget.user.isVip,
                    decoration: InputDecoration(
                      hintText: "https://example.com/my-photo.jpg",
                      suffixIcon:
                          widget.user.isVip
                              ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                              : const Icon(Icons.lock, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: !widget.user.isVip,
                      fillColor: Colors.grey[100], // ✨ ปรับสีพื้นหลัง
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  if (!widget.user.isVip)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "สมัคร VIP เพื่อเปลี่ยนรูปโปรไฟล์ของคุณ", // ✨ ข้อความแจ้ง VIP
                        style: TextStyle(color: Colors.red[400], fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "ยกเลิก",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  // ยิง API อัปเดต
                  try {
                    await http.put(
                      Uri.parse(
                        '${AppConstants.baseUrl}/user/${widget.user.id}',
                      ),
                      headers: {"Content-Type": "application/json"},
                      body: jsonEncode({
                        "display_name": nameController.text,
                        "image": imageController.text,
                        "bio": bioController.text.trim(),
                      }),
                    );

                    Navigator.pop(ctx);
                    _fetchUserStats(); // ดึงข้อมูลใหม่
                  } catch (e) {
                    print(e);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber, // ✨ สีปุ่มบันทึก
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.save),
                label: const Text("บันทึก"),
              ),
            ],
          ),
    );
  }

  // Navigation Methods
  void _navigateToFriendRequestsScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FriendRequestsScreen(currentUser: widget.user),
      ),
    );
    _fetchFriendRequestsCount();
  }

  void _navigateToTopUpScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TopupPackagesScreen(currentUser: widget.user),
      ),
    );
    _fetchUserStats();
  }

  void _navigateToVipScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VipScreen(currentUser: widget.user),
      ),
    );
    _fetchUserStats();
  }

  void _navigateToTopupHistoryScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TopupHistoryScreen(currentUser: widget.user),
      ),
    );
    _fetchUserStats(); // 🌟 เปลี่ยนเป็น fetch stats เพื่อให้ Coin Balance อัปเดต
  }

  // ✨✨✨ Method สำหรับ Leaderboard ✨✨✨
  void _navigateToLeaderboardScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMale = widget.user.gender == 'male';

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Column(
              children: [
                // --- Profile Image ---
                GestureDetector(
                  onTap: _showEditProfileDialog,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                widget.user.isVip
                                    ? Colors.amber
                                    : Colors.grey.shade300,
                            width: widget.user.isVip ? 3 : 2,
                          ),
                          boxShadow:
                              widget.user.isVip
                                  ? [
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                  : [],
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: NetworkImage(_getAvatarUrl()),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(blurRadius: 3, color: Colors.black26),
                            ],
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Name & VIP Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.user.displayName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color:
                            widget.user.isVip
                                ? Colors.amber[800]
                                : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.user.isVip)
                      const Icon(Icons.verified, color: Colors.amber, size: 20)
                    else
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isMale ? Colors.blue[100] : Colors.pink[100],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isMale ? Icons.male : Icons.female,
                          size: 16,
                          color: isMale ? Colors.blue : Colors.pink,
                        ),
                      ),
                  ],
                ),

                // ปุ่มแก้ไข (Text Button เล็กๆ)
                // profile_screen.dart: ภายใน build method (ใน Container ที่มี color: Colors.white)

// ... (โค้ดแสดงชื่อและ VIP Badge เดิม)

                // ปุ่มแก้ไข (Text Button เล็กๆ)
                Center( // จัดปุ่ม Edit ให้อยู่ตรงกลาง
                  child: TextButton.icon(
                    onPressed: _showEditProfileDialog,
                    icon: const Icon(
                      Icons.edit_note,
                      size: 16,
                      color: Colors.amber, // ✨ เปลี่ยนสีไอคอนให้เป็นสีหลัก
                    ),
                    label: const Text(
                      "แก้ไขโปรไฟล์", // ✨ เปลี่ยนเป็นภาษาไทย
                      style: TextStyle(
                        color: Colors.amber, // ✨ เปลี่ยนสีข้อความ
                        fontSize: 12,
                        fontWeight: FontWeight.bold, // ✨ เพิ่มความหนา
                      ),
                    ),
                  ),
                ),

                // 🌟 NEW: ส่วนแสดง Bio ที่ออกแบบใหม่
                const SizedBox(height: 15),
                if (_userBio.isNotEmpty)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 300), // จำกัดความกว้าง
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber[50], // ✨ สีพื้นหลังอ่อนๆ
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _userBio,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87, // ✨ เปลี่ยนเป็นสีดำเข้ม
                          fontStyle: FontStyle.italic,
                          height: 1.4, // ✨ เพิ่มระยะห่างบรรทัด
                        ),
                      ),
                    ),
                  )
                else
                  Center(
                    // กรณีไม่มี Bio
                    child: TextButton(
                      onPressed: _showEditProfileDialog,
                      child: Text(
                        "✨ เพิ่ม Bio แนะนำตัวสิ!", // ✨ ข้อความกระตุ้น
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                
                const SizedBox(height: 20), // ✨ เพิ่มระยะห่างด้านล่าง
                
// ... (Stats (Posts and Friends) เดิม)

                const SizedBox(height: 10),

                // Stats (Posts and Friends)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(
                      "Posts",
                      _isLoadingStats ? "-" : _postCount.toString(),
                    ),
                    _buildStatItem(
                      "Friends",
                      _isLoadingStats ? "-" : _friendsCount.toString(),
                    ),
                  ],
                ),

                // 🆕 ข้อมูลเพิ่มเติม (Join Date & Gender)
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // สมัครเมื่อ (Joined Date)
                      _buildStatItem(
                        "สมัครเมื่อ",
                        _isLoadingStats ? "-" : _joinedDate,
                      ),
                      const VerticalDivider(
                        width: 20,
                        thickness: 1,
                        color: Colors.grey,
                      ),
                      // เพศ (Gender)
                      _buildStatItem(
                        "เพศ",
                        widget.user.gender == 'male' ? "ชาย" : "หญิง",
                      ),
                    ],
                  ),
                ),

                // 🆕 จบส่วนข้อมูลเพิ่มเติม
                const SizedBox(height: 20),

                // Wallet Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: Colors.amber,
                            size: 36,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "เหรียญของฉัน",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                "${widget.user.coinBalance}",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _navigateToTopUpScreen,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              "เติมเหรียฯ",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),

                          ElevatedButton.icon(
                            onPressed: _navigateToVipScreen,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            icon: const Icon(
                              Icons.workspace_premium,
                              color: Colors.amber,
                              size: 16,
                            ),
                            label: const Text(
                              "VIP",
                              style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
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

          const SizedBox(height: 10),

          // Menu List
          Container(
            color: Colors.white,
            child: Column(
              children: [
                // ปุ่ม Leaderboard
                ListTile(
                  leading: const Icon(Icons.leaderboard, color: Colors.blue),
                  title: const Text("Leaderboard"),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                  onTap: _navigateToLeaderboardScreen,
                ),
                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.person_add, color: Colors.green),
                  title: const Text("New Friends"),
                  trailing:
                      _pendingRequests > 0
                          ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              _pendingRequests.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                          : const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey,
                          ),
                  onTap: _navigateToFriendRequestsScreen,
                ),

                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.mobile_friendly_outlined,
                    color: Colors.green,
                  ),
                  title: const Text("ประวัติการเติมเงิน"),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                  onTap: _navigateToTopupHistoryScreen,
                ),

                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('userId');
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Log Out",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
