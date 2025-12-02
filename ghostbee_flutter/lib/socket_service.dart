import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'constants.dart';

class SocketService {
  // สร้าง Singleton Instance
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();
  

  late IO.Socket socket;
  bool isInitialized = false;

  // Stream สำหรับส่งข้อความใหม่ไปยังทุกหน้าจอที่รอรับ
  final _newMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream =>
      _newMessageController.stream;

  // ต้องเรียก initialize ครั้งเดียวตอน Login สำเร็จ
  void initialize(int userId) {
    if (isInitialized) return;

    try {
      socket = IO.io(
        baseUrl,
        IO.OptionBuilder().setTransports(['websocket']).build(),
      );
      socket.connect();

      socket.onConnect((_) {
        print('Global Socket connected');
        // เมื่อเชื่อมต่อสำเร็จ ให้ join ห้องแชทของตัวเอง
        socket.emit('joinRoom', userId);
        isInitialized = true;
      });

      // ⚠️ รับข้อความจาก Server แล้วส่งเข้า Stream
      socket.on('receiveMessage', (data) {
        _newMessageController.add(Map<String, dynamic>.from(data));
      });

      socket.onDisconnect((_) => print('Global Socket Disconnected'));
    } catch (e) {
      print("Socket initialization error: $e");
    }
  }

  // ฟังก์ชันสำหรับส่งข้อความ (ใช้ใน ChatScreen)
  void sendMessage(Map<String, dynamic> data) {
    if (socket.connected) {
      socket.emit('sendMessage', data);
    }
  }

  // ฟังก์ชันสำหรับส่งสถานะการพิมพ์ (ใช้ใน ChatScreen)
  void emitTypingStatus(String event, int senderId, int receiverId) {
    if (socket.connected) {
      socket.emit(event, {'senderId': senderId, 'receiverId': receiverId});
    }
  }

  void emit(String event, dynamic data) {
    if (socket.connected) {
      // ใช้ emit ของ Socket.io จริง
      socket.emit(event, data);
    }
  }
  // <<< END NEW METHOD >>>


  void dispose() {
    socket.dispose();
    _newMessageController.close();
    isInitialized = false;
  }
}
