import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // จัดการวันเวลา
import './models/user.dart'; // Model User
import 'constants.dart'; // ตัวแปร baseUrl
import 'package:flutter/services.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post; // ข้อมูลโพสต์ที่ส่งมาจากหน้า Board
  final User currentUser; // ข้อมูลคน Login ปัจจุบัน

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.currentUser,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  List<dynamic> _comments = [];
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  // --- 1. Logic การแสดงเวลา ---
  String _getPostTime() {
    try {
      // แปลง String จาก Server เป็น DateTime (Local Time)
      DateTime dt = DateTime.parse(widget.post['created_at']).toLocal();
      DateTime now = DateTime.now();

      // หาผลต่างเวลา
      Duration diff = now.difference(dt);

      // ถ้าผ่านไปน้อยกว่า 5 นาที
      if (diff.inMinutes < 5) {
        return "Posted recently";
      } else {
        // ถ้าเกิน 5 นาที ให้โชว์เวลาจริง (เช่น 25-11-25 14:30)
        return DateFormat('dd-MM-yy HH:mm').format(dt);
      }
    } catch (e) {
      return "";
    }
  }

  // --- 2. ดึงคอมเมนต์ ---
  Future<void> _fetchComments() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/comments/${widget.post['id']}'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _comments = jsonDecode(response.body);
        });
      }
    } catch (e) {
      print("Error fetching comments: $e");
    }
  }

  // --- 3. ลบโพสต์ ---
  Future<void> _deletePost() async {
    // ถามยืนยันก่อนลบ
    bool confirm =
        await showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text("Delete Post"),
                content: const Text(
                  "Are you sure you want to delete this post?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      "Delete",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
        ) ??
        false;

    if (confirm) {
      try {
        await http.delete(
          Uri.parse('${AppConstants.baseUrl}/posts/${widget.post['id']}'),
        );

        if (!mounted) return;

        // ⚠️ ส่งค่า true กลับไปหน้า Board เพื่อบอกว่า "ลบแล้วนะ ให้รีเฟรชหน้าจอด้วย"
        Navigator.pop(context, true);
      } catch (e) {
        print("Delete error: $e");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Delete failed")));
      }
    }
  }

  // --- 4. ส่งคอมเมนต์ ---
  Future<void> _sendComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      await http.post(
        Uri.parse('${AppConstants.baseUrl}/comments'),
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
        }, // รองรับภาษาไทย
        body: jsonEncode({
          "post_id": widget.post['id'],
          "user_id": widget.currentUser.id,
          "content": _commentController.text,
        }),
      );

      _commentController.clear();
      FocusScope.of(context).unfocus(); // หุบคีย์บอร์ดลง
      _fetchComments(); // โหลดคอมเมนต์ใหม่
    } catch (e) {
      print("Send comment error: $e");
    }
  }

  void _showCommentOptions(Map<String, dynamic> comment) {
    // เช็คว่าเป็นคอมเมนต์เราเองหรือเปล่า (ถ้าใช่ ไม่โชว์ปุ่ม Add Friend)
    bool isMe = comment['user_id'] == widget.currentUser.id;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min, // ขนาดพอดีเนื้อหา
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              color: Colors.grey[300],
            ), // ขีดเล็กๆ
            const SizedBox(height: 10),

            // เมนู 1: Copy
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text("Copy Text"),
              onTap: () {
                // คำสั่ง Copy ลง Clipboard
                Clipboard.setData(ClipboardData(text: comment['content']));
                Navigator.pop(context); // ปิดเมนู
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Copied to clipboard")),
                );
              },
            ),

            // เมนู 2: Add Friend (โชว์เฉพาะถ้าไม่ใช่คอมเมนต์เรา)
            if (!isMe)
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.amber),
                title: const Text("Add Friend"),
                onTap: () {
                  Navigator.pop(context); // ปิดเมนู
                  _sendFriendRequest(
                    comment['user_id'],
                  ); // เรียกฟังก์ชันส่งคำขอ
                },
              ),

            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Future<void> _sendFriendRequest(int receiverId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/friend-request'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "sender_id": widget.currentUser.id,
          "receiver_id": receiverId,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Friend request sent!"),
            backgroundColor: Colors.green,
          ),
        );
      } else if (response.statusCode == 409) {
        // กรณีขอไปแล้ว หรือเป็นเพื่อนกันแล้ว
        final msg = jsonDecode(response.body)['message'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to send request"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print("Add friend error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // เช็คว่าเป็นเจ้าของโพสต์หรือไม่?
    bool isMyPost = widget.post['user_id'] == widget.currentUser.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("Post Details"),
        actions: [
          // --- ปุ่มลบ (โชว์เฉพาะเจ้าของ) ---
          if (isMyPost)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: "Delete Post",
              onPressed: _deletePost,
            ),
        ],
      ),
      body: Column(
        children: [
          // --- ส่วนบน: เนื้อหาโพสต์ ---
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          widget.post['gender'] == 'male'
                              ? Colors.blue[100]
                              : Colors.pink[100],
                      child: Icon(
                        Icons.person,
                        color:
                            widget.post['gender'] == 'male'
                                ? Colors.blue
                                : Colors.pink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post['display_name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // แสดงเวลาตาม Logic ที่เขียนไว้
                        Text(
                          _getPostTime(),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.post['content'],
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 15),
                const Divider(),
                Text(
                  "Comments (${_comments.length})",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // --- ส่วนกลาง: รายการคอมเมนต์ ---
          Expanded(
            child: ListView.builder(
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final comment = _comments[index];
                return Container(
                  color: Colors.white,
                  margin: const EdgeInsets.only(top: 1),
                  child: ListTile(
                    // ⚠️ เพิ่ม onLongPress ตรงนี้
                    onLongPress: () => _showCommentOptions(comment),

                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      radius: 16,
                      // ใช้ trick เดิมแสดงสีตามเพศ (ถ้าข้อมูล comment join gender มาแล้ว ถ้ายังไม่มีใน API comments ให้แก้ API ก่อนนะครับ หรือจะใส่เป็นสีเทาไปก่อนก็ได้)
                      backgroundColor: Colors.grey[200],
                      child: const Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                    title: Text(
                      comment['display_name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        comment['content'],
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // --- ส่วนล่าง: ช่องพิมพ์คอมเมนต์แบบ Memo ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.end, // จัดปุ่มส่งให้อยู่ล่างสุด
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _commentController,
                      keyboardType: TextInputType.multiline, // รองรับหลายบรรทัด
                      maxLines: 4, // สูงสุด 4 บรรทัด
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: "Write a memo...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CircleAvatar(
                    backgroundColor: Colors.amber,
                    radius: 22,
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: _sendComment,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
