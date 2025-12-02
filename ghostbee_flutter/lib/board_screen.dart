import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import './models/user.dart';
import 'post_detail_screen.dart';
import 'constants.dart';

class BoardScreen extends StatefulWidget {
  final User currentUser;
  const BoardScreen({super.key, required this.currentUser});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _limit = 10;

  @override
  void initState() {
    super.initState();
    _fetchPosts(isRefresh: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
              _scrollController.position.maxScrollExtent &&
          !_isLoading &&
          _hasMore) {
        _fetchPosts();
      }
    });
  }

  // --- Helper: แปลงวันที่ ---
  String _formatDate(String? dateString) {
    if (dateString == null) return "";
    try {
      DateTime dateTime = DateTime.parse(dateString);
      DateTime localDate = dateTime.toLocal();
      return DateFormat('dd-MM-yy HH:mm').format(localDate);
    } catch (e) {
      return "";
    }
  }

  // --- 1. ฟังก์ชันดึง User Data ล่าสุด ---
  Future<void> _refreshUserData() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/user/${widget.currentUser.id}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = data is Map && data.containsKey('user') ? data['user'] : data;
        
        if (mounted) {
          setState(() {
            widget.currentUser.coinBalance = userData['coin_balance'] ?? 0;
            // *สำคัญ* ถ้ามีการส่งสถานะ VIP มาด้วย ควรอัปเดตตรงนี้เช่นกัน
            // widget.currentUser.isVip = ...
          });
        }
      }
    } catch (e) {
      print("Error refreshing user data: $e");
    }
  }

  // --- 2. ฟังก์ชันดึงโพสต์ ---
  Future<void> _fetchPosts({bool isRefresh = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      if (isRefresh) {
        _currentPage = 1;
        _hasMore = true;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/posts?page=$_currentPage&limit=$_limit'),
      );

      if (response.statusCode == 200) {
        List<dynamic> newPosts = jsonDecode(response.body);
        setState(() {
          if (isRefresh) {
            _posts = newPosts;
          } else {
            for (var post in newPosts) {
              bool exists = _posts.any(
                (existingPost) => existingPost['id'] == post['id'],
              );
              if (!exists) _posts.add(post);
            }
          }
          if (newPosts.length < _limit)
            _hasMore = false;
          else
            _currentPage++;
        });
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- 3. ฟังก์ชันเปิด Dialog สร้างโพสต์ ---
  Future<void> _createPost() async {
    TextEditingController contentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Text("สร้างโพสต์ใหม่"),
            if (widget.currentUser.isVip) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified, color: Colors.amber, size: 20),
            ]
          ],
        ),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: contentController,
                  maxLength: 150,
                  onChanged: (value) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: "คุณกำลังคิดอะไรอยู่?",
                    counterText: "",
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // แสดง Coin (ถ้าเป็น VIP อาจจะไม่ต้องเน้นมาก แต่โชว์ไว้ก็ได้)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.monetization_on, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            "${widget.currentUser.coinBalance}",
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "${contentController.text.length}/150",
                      style: TextStyle(
                        fontSize: 12,
                        color: contentController.text.length > 150 ? Colors.red : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),

          // -------------------------------------------------------
          // 🛑 Logic ปุ่มกดโพสต์ (แยกตามสถานะ VIP)
          // -------------------------------------------------------
          if (widget.currentUser.isVip)
            // กรณีเป็น VIP: โชว์ปุ่มเดียว สีทอง (VIP Post)
            ElevatedButton.icon(
              icon: const Icon(Icons.stars, size: 16, color: Colors.black),
              label: const Text("VIP Post", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, // สีทอง
                elevation: 4,
              ),
              onPressed: () {
                // ส่งเป็น isBoost = true เพื่อให้ได้กรอบทอง (แต่ Backend จะไม่ตัดเงินเพราะเป็น VIP)
                _submitPostLogic(contentController.text, isBoost: true);
              },
            )
          else ...[
            // กรณี User ทั่วไป: โชว์ 2 ปุ่ม (ฟรี / เสียเงิน)
            TextButton(
              onPressed: () => _submitPostLogic(contentController.text, isBoost: false),
              child: const Text("Post Free"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.rocket_launch, size: 16, color: Colors.white),
              label: const Text("Post (-50)", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
              onPressed: () {
                _submitPostLogic(contentController.text, isBoost: true);
              },
            ),
          ]
        ],
      ),
    );
  }

  // --- 4. Logic ส่งโพสต์ ---
  Future<void> _submitPostLogic(String content, {required bool isBoost}) async {
    // Client Check: ถ้าจะ Boost และ "ไม่ใช่ VIP" ต้องเช็คเงิน
    // (ถ้าเป็น VIP ข้ามบรรทัดนี้ไปเลย)
    if (isBoost && !widget.currentUser.isVip && widget.currentUser.coinBalance < 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("เงินไม่พอ! กรุณาเติม Coin")),
      );
      return;
    }

    // Optimistic Update: ตัดเงินที่หน้าจอเฉพาะ "คนที่ไม่ใช่ VIP"
    if (isBoost && !widget.currentUser.isVip) {
      setState(() {
        widget.currentUser.coinBalance -= 50;
      });
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/posts'),
        headers: {"Content-Type": "application/json; charset=UTF-8"},
        body: jsonEncode({
          "user_id": widget.currentUser.id,
          "content": content,
          "is_boost": isBoost, // ส่งไปบอก Server (ถ้า VIP Server จะรู้เองว่าไม่ตัดเงิน)
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        Navigator.pop(context);
        _fetchPosts(isRefresh: true);
        _refreshUserData(); 
        
      } else if (response.statusCode == 403) {
        // กรณีโควต้าหมด (User ทั่วไป)
        if (isBoost && !widget.currentUser.isVip) setState(() => widget.currentUser.coinBalance += 50);

        final errorData = jsonDecode(response.body);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("😱 โควต้าฟรีหมดแล้ว!"),
            content: Text(errorData['message'] ?? "วันนี้คุณใช้สิทธิ์ฟรีครบ 5 ครั้งแล้ว"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("รอพรุ่งนี้"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                icon: const Icon(Icons.rocket_launch, size: 16, color: Colors.white),
                label: const Text("จ่าย 50 เพื่อโพสต์", style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _submitPostLogic(content, isBoost: true);
                },
              ),
            ],
          ),
        );
      } else {
        // Error อื่นๆ คืนเงิน
        if (isBoost && !widget.currentUser.isVip) setState(() => widget.currentUser.coinBalance += 50);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${response.body}")),
        );
      }
    } catch (e) {
      if (isBoost && !widget.currentUser.isVip) setState(() => widget.currentUser.coinBalance += 50);
      print("Error submitting post: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: RefreshIndicator(
        onRefresh: () => _fetchPosts(isRefresh: true),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _posts.length + 1,
          itemBuilder: (context, index) {
            if (index == _posts.length) {
              return _hasMore
                  ? const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          "No more posts",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
            }

            final post = _posts[index];
            bool isBoosted = (post['is_boost'] == 1 || post['is_boost'] == true);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: isBoosted
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF8E1), Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.amber, width: 1.5),
                    )
                  : null,
              child: Card(
                elevation: isBoosted ? 0 : 2,
                color: isBoosted ? Colors.transparent : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: isBoosted ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                child: InkWell(
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PostDetailScreen(
                          post: post,
                          currentUser: widget.currentUser,
                        ),
                      ),
                    );
                    if (result == true) {
                      _fetchPosts(isRefresh: true);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Container(
                           padding: EdgeInsets.all(isBoosted ? 2 : 0),
                           decoration: isBoosted ? const BoxDecoration(shape: BoxShape.circle, color: Colors.amber) : null,
                           child: CircleAvatar(
                            backgroundColor: post['gender'] == 'male' ? Colors.blue[100] : Colors.pink[100],
                            child: Icon(
                              Icons.person,
                              color: post['gender'] == 'male' ? Colors.blue : Colors.pink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Content: ปรับแก้ลำดับตรงนี้
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. เนื้อหาโพสต์ (Content) มาก่อน
                              Text(
                                post['content'],
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                  fontWeight: isBoosted ? FontWeight.w500 : FontWeight.normal,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8), // เพิ่มระยะห่าง

                              // 2. Header (ชื่อผู้ใช้และเวลา) ตามมาทีหลัง
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        post['display_name'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey), // ปรับ style เล็กน้อย
                                      ),
                                      if (isBoosted) ...[
                                        const SizedBox(width: 5),
                                        const Icon(Icons.rocket_launch, size: 14, color: Colors.pinkAccent),
                                      ]
                                    ],
                                  ),
                                  Text(
                                    _formatDate(post['created_at']),
                                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPost,
        backgroundColor: Colors.amber,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}