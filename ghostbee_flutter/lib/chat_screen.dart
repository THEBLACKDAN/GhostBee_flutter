import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import './models/user.dart';
import 'constants.dart';
import 'socket_service.dart';

// ⭐ เพิ่ม import emoji picker
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class ChatScreen extends StatefulWidget {
  final User currentUser;
  final Map<String, dynamic> friend;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.friend,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  List<dynamic> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;

  void Function(dynamic)? _typingStatusCallback;
  String _friendTypingStatus = '';
  Timer? _debounce;
  bool _isTyping = false;
  late StreamSubscription<Map<String, dynamic>> _chatStreamSubscription;

  // ⭐ ตัวแปรควบคุม Emoji
  bool _emojiShowing = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _listenChatStream();
  }

  // ---------------------------
  // 1. FETCH HISTORY
  // ---------------------------

  Future<void> _markMessagesAsRead() async {
    try {
      await http.put(
        Uri.parse('${AppConstants.baseUrl}/messages/mark-read'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "sender_id": widget.friend['id'],
          "receiver_id": widget.currentUser.id,
        }),
      );
    } catch (e) {
      print("Error marking messages as read: $e");
    }
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConstants.baseUrl}/messages/${widget.currentUser.id}/${widget.friend['id']}',
        ),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;

        setState(() {
          _messages = jsonDecode(response.body);
          _isLoading = false;
        });

        _scrollToBottom();
        _markMessagesAsRead();
      }
    } catch (e) {
      print("Error fetching chat history: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------
  // 2. SOCKET LISTENER
  // -------------------------------

  void _listenChatStream() {
    if (!SocketService().isInitialized) {
      print("Socket Service not initialized.");
      return;
    }

    _chatStreamSubscription = SocketService().messageStream.listen((data) {
      if (!mounted) return;

      if ((data['sender_id'] == widget.currentUser.id &&
              data['receiver_id'] == widget.friend['id']) ||
          (data['sender_id'] == widget.friend['id'] &&
              data['receiver_id'] == widget.currentUser.id)) {
        setState(() => _messages.add(data));
        _scrollToBottom();
      }
    });

    _typingStatusCallback = (data) {
      if (!mounted) return;

      if (data['userId'] == widget.friend['id']) {
        setState(() => _friendTypingStatus = data['status']);

        if (_friendTypingStatus == 'typing...') _scrollToBottom();
      }
    };

    SocketService().socket.on('typingStatus', _typingStatusCallback!);

    SocketService().socket.on('messagesRead', (data) {
      if (!mounted) return;

      if (data['readerId'] == widget.friend['id'] &&
          data['senderId'] == widget.currentUser.id) {
        setState(() {
          _messages =
              _messages.map((msg) {
                if (msg['sender_id'] == widget.currentUser.id &&
                    msg['is_read'] != true) {
                  final newMsg = Map<String, dynamic>.from(msg);
                  newMsg['is_read'] = true;
                  return newMsg;
                }
                return msg;
              }).toList();
        });
      }
    });
  }

  // -------------------------------
  // 3. TYPING STATUS
  // -------------------------------

  void _onTextChanged(String text) {
    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      SocketService().emitTypingStatus(
        'typing',
        widget.currentUser.id,
        widget.friend['id'],
      );
      _resetDebounceTimer();
    } else if (text.isNotEmpty) {
      _resetDebounceTimer();
    } else if (text.isEmpty && _isTyping) {
      _isTyping = false;
      SocketService().emitTypingStatus(
        'stopTyping',
        widget.currentUser.id,
        widget.friend['id'],
      );
      _debounce?.cancel();
    }
  }

  void _resetDebounceTimer() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_isTyping) {
        _isTyping = false;
        SocketService().emitTypingStatus(
          'stopTyping',
          widget.currentUser.id,
          widget.friend['id'],
        );
      }
    });
  }

  // ---------------------------
  // 4. SEND MESSAGE
  // ---------------------------

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final messageData = {
      'senderId': widget.currentUser.id,
      'receiverId': widget.friend['id'],
      'content': text,
    };

    SocketService().sendMessage(messageData);

    _msgController.clear();
    FocusScope.of(context).unfocus();

    _isTyping = false;
    _debounce?.cancel();
    SocketService().emitTypingStatus(
      'stopTyping',
      widget.currentUser.id,
      widget.friend['id'],
    );

    // ❗ ปิด emoji เวลาเซ็นต์ข้อความ
    setState(() => _emojiShowing = false);
  }

  // ---------------------------
  // 5. SCROLL TO BOTTOM
  // ---------------------------

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _msgController.dispose();
    _debounce?.cancel();

    _chatStreamSubscription.cancel();
    if (SocketService().isInitialized && _typingStatusCallback != null) {
      SocketService().socket.off('typingStatus', _typingStatusCallback!);
    }
    super.dispose();
  }

  // ---------------------------
  // 6. UI : MESSAGE BUBBLE
  // ---------------------------

  Widget _buildMessage(Map<String, dynamic> msg) {
    bool isMe = msg['sender_id'] == widget.currentUser.id;

    DateTime dt = DateTime.parse(msg['created_at']).toLocal();
    final timeStr = DateFormat('HH:mm').format(dt);

    bool isRead = msg['is_read'] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
            margin: EdgeInsets.only(
              top: 5,
              left: isMe ? 80 : 10,
              right: isMe ? 10 : 80,
            ),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(15),
                topRight: const Radius.circular(15),
                bottomLeft: Radius.circular(isMe ? 15 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 15),
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 1),
              ],
            ),
            child: Text(
              msg['content'],
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 0 : 10,
              right: isMe ? 10 : 0,
              bottom: 15,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
                const SizedBox(width: 4),
                if (isMe)
                  isRead
                      ? const Text(
                        "seen",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      : const Icon(Icons.done, size: 14, color: Colors.black45),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 10, top: 5),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundImage: NetworkImage(
              "https://i.pravatar.cc/150?img=${widget.friend['id'] + 10}",
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "Typing...",
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // 7. BUILD UI
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_emojiShowing) {
          setState(() => _emojiShowing = false);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.friend['display_name'],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _friendTypingStatus.isEmpty ? 'Online' : _friendTypingStatus,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      _friendTypingStatus.isEmpty
                          ? Colors.white70
                          : Colors.lightGreenAccent,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.amber,
          foregroundColor: Colors.white,
          elevation: 1,
        ),

        body: Column(
          children: [
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(top: 10),
                        itemCount:
                            _messages.length +
                            (_friendTypingStatus == 'typing...' ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _messages.length) {
                            return _buildTypingIndicator();
                          }
                          return _buildMessage(_messages[i]);
                        },
                      ),
            ),

            // ---------------------------
            // ⭐ INPUT + EMOJI BUTTON
            // ---------------------------
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.grey[50],
              child: Row(
                children: [
                  // ⭐ ปุ่มเปิด emoji picker
                  IconButton(
                    icon: const Icon(
                      Icons.emoji_emotions_outlined,
                      color: Colors.amber,
                    ),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _emojiShowing = !_emojiShowing);
                    },
                  ),

                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: _onTextChanged,
                      onTap: () {
                        if (_emojiShowing) {
                          setState(() => _emojiShowing = false);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 5),
                  CircleAvatar(
                    backgroundColor: Colors.amber,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),

            // ---------------------------
            // ⭐ EMOJI PICKER แสดงตรงนี้
            // ---------------------------
            Offstage(
              offstage: !_emojiShowing,
              child: SizedBox(
                height: 260,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    _msgController.text += emoji.emoji;
                  },
                  config: const Config(
                    columns: 7,
                    emojiSizeMax: 32,
                    verticalSpacing: 0,
                    horizontalSpacing: 0,
                    initCategory: Category.SMILEYS,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
