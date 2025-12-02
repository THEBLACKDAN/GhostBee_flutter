import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'socket_service.dart';
import './models/user.dart';
import 'package:collection/collection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// ----------------------------------------------------
// ClubRoomScreen: หน้าห้องแชท Club พร้อม Timer และ End Club
// ----------------------------------------------------

class ClubRoomScreen extends StatefulWidget {
  final User currentUser;
  final int clubId;
  final String clubName;
  final int ownerId;
  final VoidCallback onClubEnd;

  const ClubRoomScreen({
    super.key,
    required this.currentUser,
    required this.clubId,
    required this.clubName,
    required this.ownerId,
    required this.onClubEnd,
  });

  @override
  State<ClubRoomScreen> createState() => _ClubRoomScreenState();
}

class _ClubRoomScreenState extends State<ClubRoomScreen> {
  // ----------------------------------------------------
  // 1. STATE & VARIABLES
  // ----------------------------------------------------

  Map<String, dynamic>? _clubData;
  bool _isLoading = true;
  Duration _remainingTime = Duration.zero;
  int _memberCount = 1;

  // State สำหรับเก็บรายชื่อสมาชิกทั้งหมดที่อยู่ใน DB (รวม Speaker/Listener)
  List<Map<String, dynamic>> _allMembers = [];

  // Socket & Timer
  Timer? _clubTimer;
  late StreamSubscription<Map<String, dynamic>> _clubStreamSubscription;

  // --- Stage Data ---
  List<Map<String, dynamic>?> stageSlots = [null, null, null];

  // 🆕 [WebRTC]: Map เก็บ Peer Connections สำหรับการพูด/ฟัง
  final Map<int, RTCPeerConnection> _peerConnections = {};

  // 🆕 [WebRTC]: Map เก็บ Media Stream สำหรับผู้พูดแต่ละคน
  final Map<int, MediaStream> _remoteAudioStreams = {};

  // 🆕 [WebRTC]: Map เก็บ Renderer สำหรับเล่นเสียง (แม้จะไม่มีภาพก็ต้องใช้)
  final Map<int, RTCVideoRenderer> _remoteRenderers = {};

  // 🆕 [WebRTC]: Local Stream (เสียงของเรา)
  MediaStream? _localAudioStream;
  bool _isMuted = false;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ],
  };

  // List สำหรับ Listener (คนที่ไม่ได้อยู่บน Stage)
  List<Map<String, dynamic>> get _listeners {
    final onStageIds =
        stageSlots.where((s) => s != null).map((s) => s!['id']).toSet();

    // กรองสมาชิกทั้งหมดออกด้วย ID ที่อยู่บน Stage
    return _allMembers
        .where((member) => !onStageIds.contains(member['id']))
        .toList();
  }

  bool get amIOnStage => stageSlots.any(
    (user) => user != null && user['id'] == widget.currentUser.id,
  );

  bool get amITheOwner => widget.currentUser.id == widget.ownerId;

  // ----------------------------------------------------
  // 2. LIFECYCLE & INITIALIZATION
  // ----------------------------------------------------

  @override
  void initState() {
    super.initState();
    _fetchClubDetails();
    _listenClubEvents();

    // ส่ง joinClub ไปยัง Server
    SocketService().emit('joinClub', {
      'clubId': widget.clubId,
      'userId': widget.currentUser.id,
    });
  }

  @override
  void dispose() {
    _cleanupWebRTC();
    SocketService().emit('leaveClub', widget.clubId);
    _clubTimer?.cancel();
    _clubStreamSubscription.cancel();
    super.dispose();
  }

  // 🆕 [WebRTC] ฟังก์ชันสำหรับปิดการเชื่อมต่อทั้งหมด
  void _cleanupWebRTC() async {
    // ปิด Local Stream
    _localAudioStream?.getTracks().forEach((track) => track.stop());
    await _localAudioStream?.dispose();
    _localAudioStream = null;

    // ปิด Remote Streams และ Peer Connections
    _remoteAudioStreams.forEach((id, stream) => stream.dispose());
    _remoteAudioStreams.clear();

    // 🛑 [FIX]: ปิด Peer Connection ทีละตัว
    for (var pc in _peerConnections.values) {
      if (pc.iceConnectionState !=
          RTCIceConnectionState.RTCIceConnectionStateClosed) {
        await pc.close();
      }
    }
    _peerConnections.clear();

    // 🛑 [FIX]: Dispose Renderer ทั้งหมด
    _remoteRenderers.forEach((key, renderer) => renderer.dispose());
    _remoteRenderers.clear();
  }

  // 🆕 [WebRTC]: ฟังก์ชันช่วยในการสร้างและผูก Stream เข้ากับ Renderer
  Future<void> _ensureRemoteRenderer(int userId, MediaStream stream) async {
    if (!_remoteRenderers.containsKey(userId)) {
      // 1. สร้างและ Initialize Renderer ใหม่
      final renderer = RTCVideoRenderer();
      await renderer.initialize();

      // 2. เก็บเข้า Map
      _remoteRenderers[userId] = renderer;

      // 3. ผูก Stream เพื่อให้เสียงเริ่มเล่น (แม้จะไม่เห็นภาพ)
      renderer.srcObject = stream;

      setState(() {
        // อัปเดต Map หลักเพื่อให้ UI รู้ว่ามี Stream แล้ว
        _remoteAudioStreams[userId] = stream;
      });
    } else {
      // ถ้า Renderer มีอยู่แล้ว ก็ผูก Stream ซ้ำ (กรณี Re-negotiation)
      _remoteRenderers[userId]!.srcObject = stream;
    }
  }

  // 🆕 [WebRTC]: ฟังก์ชันสำหรับล้าง Peer Connection และ Renderer
  void _closePeerConnection(int targetUserId) async {
    // ปิด Peer Connection
    if (_peerConnections.containsKey(targetUserId)) {
      await _peerConnections[targetUserId]?.close();
      _peerConnections.remove(targetUserId);
    }

    // Dispose Renderer
    if (_remoteRenderers.containsKey(targetUserId)) {
      await _remoteRenderers[targetUserId]!.dispose();
      _remoteRenderers.remove(targetUserId);
    }

    // ลบออกจาก Map Stream
    if (_remoteAudioStreams.containsKey(targetUserId)) {
      setState(() {
        _remoteAudioStreams.remove(targetUserId);
      });
    }
  }

  // ----------------------------------------------------
  // 3. API & SOCKET LOGIC (รวม WebRTC Signaling)
  // ----------------------------------------------------

  // ฟังก์ชันดึงรายชื่อสมาชิก Club
  Future<void> _fetchClubMembers() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/clubs/${widget.clubId}/members'),
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final members = List<Map<String, dynamic>>.from(data['members']);

        // กรองหา Owner/Admin
        final ownerMember = members.firstWhereOrNull(
          (m) => m['id'] == widget.ownerId,
        );

        // Logic การวาง Owner บน Stage Slot 0 เมื่อเข้าห้องครั้งแรก
        if (ownerMember != null && stageSlots[0] == null) {
          stageSlots[0] = {
            "name": ownerMember['name'],
            "image":
                ownerMember['image'] ??
                "https://i.pravatar.cc/150?img=${widget.ownerId}",
            "id": widget.ownerId,
          };
        }

        setState(() {
          _allMembers = members;
          _memberCount = _allMembers.length;
        });
      } else {
        _showSnackbar(
          "Failed to load club members: ${response.statusCode}",
          isError: true,
        );
      }
    } catch (e) {
      if (mounted)
        _showSnackbar("Network Error fetching members: $e", isError: true);
    }
  }

  Future<void> _fetchClubDetails() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/clubs/${widget.clubId}'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final club = data['club'];

        if (club == null) {
          return _showClubExpiredDialog(
            isServerForce: false,
            title: "Club Closed",
            message: "This club was closed while you were joining.",
          );
        }

        setState(() {
          _clubData = club;
          _isLoading = false;

          final expiryTime = DateTime.parse(club['expires_at']);
          _remainingTime = expiryTime.difference(DateTime.now());
        });

        await _fetchClubMembers();

        if (_remainingTime.inSeconds > 0) {
          _startClubTimer();
        } else {
          _showClubExpiredDialog(isServerForce: false);
        }
      } else if (response.statusCode == 404) {
        _showClubExpiredDialog(
          isServerForce: false,
          title: "Club Closed",
          message: "This club does not exist or has already expired.",
        );
      } else {
        _showErrorDialog("Failed to load club details: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) _showErrorDialog("Network Error: $e");
    }
  }

  void _startClubTimer() {
    _clubTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_remainingTime.inSeconds > 0) {
          _remainingTime = _remainingTime - const Duration(seconds: 1);
        } else {
          timer.cancel();
        }
      });
    });
  }

  // ⚠️ [WebRTC] ฟังก์ชันเริ่ม Local Audio Stream (เมื่อขึ้น Stage)
  Future<void> _startLocalStream() async {
    try {
      final mediaDevices = navigator.mediaDevices;
      // ⚠️ [FIXED]: เพิ่ม check stream == null
      final stream = await mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      if (stream == null) {
        throw Exception(
          "getUserMedia returned null stream. Permission denied or device error.",
        );
      }

      setState(() {
        _localAudioStream = stream;
        _isMuted = false;
      });

      if (amIOnStage) {
        _initiateWebRTCSignaling();
      }
    } catch (e) {
      print("WebRTC StartLocalStream Error: $e");
      _showErrorDialog("Failed to access microphone. Error: ${e.toString()}");
      setState(() {
        _localAudioStream = null;
      });
    }
  }

  // ⚠️ [WebRTC] ฟังก์ชันเริ่ม Signaling (ผู้พูด)
  void _initiateWebRTCSignaling() async {
    // วนลูปสร้าง Offer สำหรับสมาชิกทุกคนในห้อง (ยกเว้นตัวเราเอง)
    for (var member in _allMembers) {
      final targetUserId = member['id'] as int;

      if (targetUserId != widget.currentUser.id) {
        // 1. สร้าง Peer Connection
        final peer = await _createPeerConnection(targetUserId);
        _peerConnections[targetUserId] = peer;

        // 2. เพิ่ม Local Track (เสียงของเรา)
        if (_localAudioStream != null) {
          // 🛑 [FIX]: เปลี่ยนจาก addStream เป็น addTrack
          _localAudioStream!.getTracks().forEach((track) {
            peer.addTrack(track, _localAudioStream!);
          });
        }

        // 3. สร้าง Offer และส่งผ่าน Signaling Server
        final offer = await peer.createOffer();
        await peer.setLocalDescription(offer);

        SocketService().emit('sendOffer', {
          'targetUserId': targetUserId,
          'offer': offer.toMap(), // ส่ง Map ของ Offer
        });
      }
    }
  }

  // ⚠️ [WebRTC] สร้าง RTCPeerConnection และกำหนด Listener
  Future<RTCPeerConnection> _createPeerConnection(int targetUserId) async {
    final pc = await createPeerConnection(_iceServers, {});

    // 1. ICE Candidate Listener: ส่ง Candidate ไปให้ผู้ใช้เป้าหมาย
    pc.onIceCandidate = (candidate) {
      if (candidate != null) {
        SocketService().emit('sendIceCandidate', {
          'targetUserId': targetUserId,
          'candidate': candidate.toMap(),
        });
      }
    };

    // ⚠️ [FIX]: ตรวจสอบ Ice Connection Status เพื่อล้าง PC เมื่อหลุด
    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        print("ICE Connection to $targetUserId State: $state. Cleaning up.");
        _closePeerConnection(targetUserId);
      }
    };

    // 2. Track Listener: สำหรับผู้ฟัง เมื่อได้รับ Track เสียงจากผู้พูด
    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        final remoteStream = event.streams[0]; // ดึง Stream ที่มี Track นี้อยู่

        if (!mounted) return;

        // 🛑 [FIX]: เรียกใช้ฟังก์ชันจัดการ Renderer ทันทีที่ได้ Stream
        _ensureRemoteRenderer(targetUserId, remoteStream);
      }
    };
    return pc;
  }

  // ⚠️ [WebRTC] ฟังก์ชันจัดการ WebRTC Signaling Events (Offer/Answer/Candidate)
  void _handleWebRTCEvent(Map<String, dynamic> event) async {
    final webrtcEvent = event['webrtcEvent'];
    final senderId = event['senderId'] as int;

    // 1. ตรวจสอบว่า Connection นี้ถูกปิดไปแล้วหรือยัง
    final existingPc = _peerConnections[senderId];
    if (existingPc != null &&
        existingPc.iceConnectionState ==
            RTCIceConnectionState.RTCIceConnectionStateClosed) {
      print("Ignoring WebRTC event: Connection with $senderId is closed.");
      return;
    }

    if (_peerConnections[senderId] == null && webrtcEvent != 'offer') {
      return;
    }

    if (webrtcEvent == 'offer') {
      // 1. เราเป็นผู้ฟัง/Speaker ที่ได้รับ Offer
      final offer = RTCSessionDescription(
        event['offer']['sdp'],
        event['offer']['type'],
      );

      // สร้าง Peer Connection (ถ้ายังไม่มี)
      final pc = await _createPeerConnection(senderId);
      _peerConnections[senderId] = pc;

      // ... (โค้ด setRemoteDescription, createAnswer, setLocalDescription, sendAnswer เหมือนเดิม)
      await pc.setRemoteDescription(offer);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      SocketService().emit('sendAnswer', {
        'targetUserId': senderId,
        'answer': answer.toMap(),
      });
    } else if (webrtcEvent == 'answer') {
      // 2. เราเป็นผู้พูด (Speaker) ได้รับ Answer จาก Listener/Speaker
      final answer = RTCSessionDescription(
        event['answer']['sdp'],
        event['answer']['type'],
      );
      final pc = _peerConnections[senderId];
      if (pc != null) {
        await pc.setRemoteDescription(answer);
      }
    } else if (webrtcEvent == 'candidate') {
      // 3. ได้รับ ICE Candidate
      final candidate = RTCIceCandidate(
        event['candidate']['candidate'],
        event['candidate']['sdpMid'],
        event['candidate']['sdpMLineIndex'],
      );
      final pc = _peerConnections[senderId];
      if (pc != null) {
        await pc.addCandidate(candidate);
      }
    }
  }

  // ⚠️ [FIXED] แก้ไข Logic การฟัง Event
  void _listenClubEvents() {
    _clubStreamSubscription = SocketService().messageStream.listen((
      event,
    ) async {
      if (!mounted) return;

      final messageContent = event['message'];

      // 1. Real-time Member Update
      if (event.containsKey('members') && event['members'] is int) {
        await _fetchClubMembers();
      }
      // 2. Club Expired/Closed Event
      else if (messageContent != null && messageContent is String) {
        final normalizedMessage = messageContent.toLowerCase();

        if (normalizedMessage.contains('was manually ended') ||
            normalizedMessage.contains('has expired')) {
          _clubTimer?.cancel();
          _showClubExpiredDialog(
            isServerForce: true,
            message: messageContent,
            title:
                normalizedMessage.contains('manually ended')
                    ? "Club Ended by Owner"
                    : "Time's Up!",
          );
        }
      }
      // 3. Stage Update (Real-time Speaker/Listener status)
      else if (event.containsKey('stageSlots')) {
        _handleStageUpdate(event);
      }
      // 🆕 [WebRTC]: 4. WebRTC Signaling (Offer, Answer, Candidate)
      else if (event.containsKey('webrtcEvent')) {
        _handleWebRTCEvent(event);
      }
    });
  }

  // 🆕 [เพิ่ม]: ฟังก์ชันจัดการ Stage Update Payload
  void _handleStageUpdate(Map<String, dynamic> event) {
    final List<dynamic> receivedSlots = event['stageSlots'];

    final newStageSlots =
        receivedSlots.map((slot) {
          if (slot == null) return null;
          return Map<String, dynamic>.from(slot);
        }).toList();

    setState(() {
      stageSlots = newStageSlots;
    });

    // ⚠️ ถ้า Stage เปลี่ยน ต้องอัปเดตการเชื่อมต่อ WebRTC ด้วย
    if (amIOnStage) {
      _initiateWebRTCSignaling(); // ผู้พูด: ส่ง Offer ใหม่ให้สมาชิกที่เข้า/ออก
    }
  }

  Future<void> _endClub() async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/clubs/${widget.clubId}'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        // Success: รอรับ Socket Event เพื่อปิดหน้าจอ
      } else {
        _showErrorDialog("Failed to end club: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) _showErrorDialog("Network Error ending club: $e");
    }
  }

  // ----------------------------------------------------
  // 4. UI LOGIC & DIALOGS (มีการปรับ _toggleStageSlot)
  // ----------------------------------------------------

  void _toggleStageSlot(int index) async {
    if (_isLoading) return;

    Map<String, dynamic>? newSlotData;

    if (stageSlots[index] != null) {
      // 1. ถ้ามีคนอยู่แล้ว (ลง Stage)
      if (stageSlots[index]!['id'] == widget.currentUser.id) {
        newSlotData = null;
        _cleanupWebRTC(); // 🆕 ปิดการเชื่อมต่อทั้งหมดเมื่อลง Stage
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You left the stage. Audio stopped.")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "This seat is taken by ${stageSlots[index]!['name']}",
            ),
          ),
        );
        return;
      }
    } else {
      // 2. ถ้า Stage ว่าง (ขึ้น Stage)
      if (amIOnStage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You are already on the stage!")),
        );
        return;
      } else {
        newSlotData = {
          "name": widget.currentUser.displayName,
          "image":
              widget.currentUser.image ??
              "https://i.pravatar.cc/150?img=${widget.currentUser.id + 10}",
          "id": widget.currentUser.id,
        };
        // 🆕 [WebRTC]: เริ่ม Audio Stream ทันทีที่ขึ้น Stage
        await _startLocalStream();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You are now on the stage! Tap again to leave."),
          ),
        );
      }
    }

    setState(() {
      stageSlots[index] = newSlotData;
    });

    // ส่ง Stage Slots ชุดใหม่ไปยัง Server
    SocketService().emit('updateStage', {
      'clubId': widget.clubId,
      'stageSlots': stageSlots,
    });
  }

  // ⚠️ [WebRTC] ฟังก์ชัน Mute/Unmute
  void _toggleMute() {
    if (_localAudioStream != null) {
      // 🛑 [FIXED]: ใช้ firstWhereOrNull และ check null
      final audioTrack = _localAudioStream!.getAudioTracks().firstWhereOrNull(
        (track) => track.kind == 'audio',
      );

      if (audioTrack != null) {
        audioTrack.enabled = !_isMuted;
        setState(() {
          _isMuted = !_isMuted;
        });
      }
    }
  }

  // ----------------------------------------------------
  // 4.1. DIALOGS (โค้ดเดิม)
  // ----------------------------------------------------

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

  void _showClubExpiredDialog({
    required bool isServerForce,
    String title = "Club Closed",
    String message = "The club room has ended.",
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: Text(title), // ใช้ Title ที่ส่งเข้ามา
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx); // 1. ปิด Dialog
                  widget.onClubEnd(); // 2. บอก Club List ให้รีเฟรช
                  Navigator.pop(context); // 3. ปิดหน้า ClubRoom
                },
                child: const Text("OK", style: TextStyle(color: Colors.amber)),
              ),
            ],
          ),
    );
  }

  void _showEndClubConfirmationDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("End Club?"),
            content: const Text(
              "Are you sure you want to close this club room? It will be permanently deleted and all members will be disconnected.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // ปิด confirmation dialog
                  _endClub(); // เรียก API
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  "End Club",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Error"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Close"),
              ),
            ],
          ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: color,
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // ----------------------------------------------------
  // 5. UI COMPONENTS & BUILD
  // ----------------------------------------------------

  Widget _buildStageSlot(int index, Map<String, dynamic>? user) {
    final isOccupied = user != null;
    final isMe = isOccupied && user['id'] == widget.currentUser.id;
    // อนุญาตให้แตะได้ถ้า Stage ว่าง หรือมีเราอยู่แล้ว
    final isStageInteractable = !isOccupied || isMe;

    // 🆕 [WebRTC]: เช็คว่า Speaker คนนี้มี Audio Stream ส่งมาถึงเราหรือไม่
    final hasAudioStream = _remoteAudioStreams.containsKey(user?['id']);

    return GestureDetector(
      onTap: isStageInteractable ? () => _toggleStageSlot(index) : null,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    isMe
                        ? Colors.greenAccent
                        : isOccupied
                        ? Colors.amber
                        : Colors.grey[300]!,
                width: 3,
              ),
              color: isOccupied ? Colors.white : Colors.grey[200],
              boxShadow:
                  isOccupied
                      ? [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                      : [],
            ),
            child:
                isOccupied
                    ? ClipOval(
                      child: Image.network(
                        user['image'],
                        fit: BoxFit.cover,
                        // แสดง Icon แทนถ้าโหลดรูปไม่ได้
                        errorBuilder:
                            (context, error, stackTrace) => const Icon(
                              Icons.person,
                              size: 40,
                              color: Colors.grey,
                            ),
                      ),
                    )
                    : const Icon(Icons.add, size: 40, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isOccupied ? Colors.black87 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isOccupied
                  ? (isMe ? "Me (${user['name']})" : user['name'])
                  : "Tap to Speak",
              style: TextStyle(
                color: isOccupied ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: isOccupied ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isOccupied)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                isMe && _isMuted
                    ? Icons
                        .mic_off // เราถูก Mute
                    : hasAudioStream || isMe
                    ? Icons
                        .mic // Speaker/เรากำลังพูด
                    : Icons.mic_none, // Speaker แต่ยังไม่มี Stream มาถึง
                size: 14,
                color: isMe && _isMuted ? Colors.redAccent : Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String timeString =
        "${_remainingTime.inMinutes.remainder(60).toString().padLeft(2, '0')}:"
        "${_remainingTime.inSeconds.remainder(60).toString().padLeft(2, '0')}";

    // ใช้ _listeners.length แทนการคำนวณจาก _memberCount
    final listenerCount = _listeners.length;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.clubName)),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.clubName, style: const TextStyle(fontSize: 18)),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 12,
                  color: Colors.lightGreenAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  "Time Left: $timeString",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: Colors.lightGreenAccent,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.group, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  "Online: $_memberCount",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (amITheOwner)
            TextButton(
              onPressed: _showEndClubConfirmationDialog,
              child: const Text(
                "End Club",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                stageSlots.length,
                (index) => _buildStageSlot(index, stageSlots[index]),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Listeners ($listenerCount)", // แสดงจำนวน Listener ที่ไม่ได้อยู่บน Stage
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.7,
                          ),
                      itemCount: _listeners.length, // ใช้จำนวน Listener ตัวจริง
                      itemBuilder: (context, index) {
                        final user =
                            _listeners[index]; // ใช้ข้อมูล Listener ตัวจริง
                        return Column(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[200],
                                image: DecorationImage(
                                  image: NetworkImage(
                                    // ใช้ image จากข้อมูลจริง ถ้าไม่มีให้ fallback
                                    user['image'] ??
                                        "https://i.pravatar.cc/150?img=${user['id']}",
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user['name']!,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 🆕 [WebRTC]: ปุ่มควบคุมเสียงเมื่ออยู่บน Stage
          if (amIOnStage)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 5,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildControlBtn(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? "Unmute" : "Mute",
                    color: _isMuted ? Colors.red : Colors.green,
                    onTap: _toggleMute,
                  ),
                  _buildControlBtn(
                    icon: Icons.waving_hand,
                    label: "Leave Stage",
                    color: Colors.amber,
                    onTap: () {
                      final index = stageSlots.indexWhere(
                        (user) =>
                            user != null && user['id'] == widget.currentUser.id,
                      );
                      if (index != -1) _toggleStageSlot(index);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
