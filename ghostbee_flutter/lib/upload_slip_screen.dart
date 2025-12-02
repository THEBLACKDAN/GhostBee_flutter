// UploadSlipScreen.dart

import 'dart:io';
import 'dart:ui' as ui; // ใช้สำหรับ ImageByteFormat
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; 
import 'package:ghostbee_flutter/TopupStatusScreen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart'; // 🌟 ใช้ตัวนี้
import 'package:permission_handler/permission_handler.dart'; // 🌟 ใช้ตัวนี้
import 'dart:convert';
import 'dart:typed_data'; 
import '../models/user.dart';
import '../constants.dart'; 


class UploadSlipScreen extends StatefulWidget {
  final int amount;
  final User currentUser;

  UploadSlipScreen({
    required this.amount,
    required this.currentUser,
  });

  @override
  State<UploadSlipScreen> createState() => _UploadSlipScreenState();
}

class _UploadSlipScreenState extends State<UploadSlipScreen> {
  String? qrBase64;
  XFile? slipFile;      
  Uint8List? slipBytes; 
  String? fileName;      
  
  int? historyId;      // ID รายการที่ได้จาก prepare-payment
  double? uniqueAmount; // ยอดเงินที่มีเศษสตางค์ที่ต้องโอน
  
  bool loading = false;
  
  // 🌟 GlobalKey สำหรับจับ Widget QR Code เพื่อบันทึกรูป
  final GlobalKey _qrKey = GlobalKey(); 

  // -----------------------------
  // สมมติชื่อบัญชีที่รับโอน (ตาม PromptPay number ใน payment.js)
  final String promptPayRecipientName = "นาย ปฏิมา รุ่งจวี";
  // -----------------------------

  @override
  void initState() {
    super.initState();
    _fetchQR();
  }

  // -----------------------------
  // โหลด QR จาก API /prepare-payment
  // -----------------------------
  Future<void> _fetchQR() async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/payment/prepare-payment"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': widget.amount, 
          'user_id': widget.currentUser.id,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          qrBase64 = data["qr"];
          historyId = data["history_id"]; 
          uniqueAmount = data["unique_amount"];
        });
      } else {
         print("Failed to prepare payment: ${response.statusCode}");
         _showError("ไม่สามารถสร้างรายการชำระเงินได้");
      }
    } catch (e) {
      print("QR Load Error: $e");
      _showError("QR Load Error: $e");
    }
  }

  // -----------------------------
  // Upload Slip
  // -----------------------------
  Future uploadSlip() async {
    if (slipFile == null || slipBytes == null || historyId == null) return; 

    setState(() => loading = true);

    var request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/payment/upload-slip"),
    );

    request.fields['user_id'] = widget.currentUser.id.toString();
    request.fields['history_id'] = historyId.toString(); 

    request.files.add(
      http.MultipartFile.fromBytes(
        "slip", 
        slipBytes!, 
        filename: slipFile!.name, 
      ),
    );

    var response = await request.send();
    String result = await response.stream.bytesToString();
    final data = jsonDecode(result);

    setState(() => loading = false);

    // จัดการการตอบกลับ Pending (202 Accepted)
    if (response.statusCode == 202 && data["status"] == "pending") {
        _navigateToStatusCheck(data["history_id"]); 
    } else {
        _showError(data["message"] ?? "เกิดข้อผิดพลาดในการส่งสลิป");
    }
  }
  
  // -----------------------------
  // 🆕 ฟังก์ชันสำหรับบันทึก QR Code (ใช้งานจริง)
  // -----------------------------
  Future<void> _saveQrCode() async {
    if (qrBase64 == null) return;
    
    try {
      // 1. ขอสิทธิ์การเข้าถึง Storage
      if (await Permission.storage.request().isGranted) {
        
        // 2. จับภาพ Widget (QR Code)
        final RenderRepaintBoundary boundary =
            _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();

        // 3. บันทึกภาพ
        final result = await ImageGallerySaver.saveImage(
          pngBytes,
          name: "PromptPay_Topup_${historyId}",
        );
        
        // 4. แจ้งผลลัพธ์
        if (result['isSuccess']) {
           _showInfo("บันทึก QR Code สำเร็จ!");
        } else {
           _showError("บันทึก QR Code ล้มเหลว");
        }
      } else {
        _showError("ไม่ได้รับอนุญาตให้เข้าถึงที่เก็บข้อมูล");
      }
    } catch (e) {
      print("Save QR Error: $e");
      _showError("เกิดข้อผิดพลาดในการบันทึก: $e");
    }
  }
  
  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // -----------------------------
  // UI: Error Popup
  // -----------------------------
  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("ผิดพลาด"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  // 🌟 ฟังก์ชันนำทางไปหน้าตรวจสอบสถานะ (ไม่ได้เปลี่ยน)
  void _navigateToStatusCheck(int historyId) {
    Navigator.pushReplacement( 
      context,
      MaterialPageRoute(
        builder: (context) => TopupStatusScreen(
          historyId: historyId,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("ชำระเงิน ${widget.amount} บาท")),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(15),
          child: Column(
            children: [
              Text(
                "สแกน QR พร้อมเพย์เพื่อชำระเงิน ${widget.amount} บาท", 
                style: TextStyle(fontSize: 18),
              ),

              SizedBox(height: 15),
              
              // 🆕 แสดงชื่อผู้รับโอน
              Text(
                "ผู้รับโอน: **$promptPayRecipientName**",
                style: TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 10),
              
              // แสดงยอดเงินที่มีเศษสตางค์
              if (uniqueAmount != null)
                Text(
                  "กรุณาโอนเงิน **${uniqueAmount!.toStringAsFixed(2)} บาท** เท่านั้น",
                  style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),

              SizedBox(height: 15),

              // ---------- QR FROM SERVER ----------
              qrBase64 == null
                  ? CircularProgressIndicator()
                  : RepaintBoundary( // 🌟 Wrap ด้วย RepaintBoundary เพื่อใช้ GlobalKey บันทึกภาพ
                      key: _qrKey,
                      child: Image.memory(
                        base64Decode(qrBase64!),
                        width: 260,
                        // ไม่ต้องใส่ color: Colors.white; เพราะ Base64 Image ควรมีพื้นหลังอยู่แล้ว
                      ),
                    ),

              SizedBox(height: 10),
              
              // 🆕 ปุ่มบันทึก QR Code
              if (qrBase64 != null)
                TextButton.icon(
                  onPressed: _saveQrCode,
                  icon: Icon(Icons.download),
                  label: Text("บันทึก QR Code"),
                ),
              
              Divider(height: 30),

              ElevatedButton(
                onPressed: () async {
                  final picked = await ImagePicker()
                      .pickImage(source: ImageSource.gallery);

                  if (picked != null) {
                    final bytes = await picked.readAsBytes(); 
                    setState(() {
                      slipFile = picked;
                      slipBytes = bytes;
                      fileName = picked.name; 
                    });
                  }
                },
                child: Text("เลือกสลิปโอนเงิน"),
              ),

              if (fileName != null)
                Column(
                  children: [
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image, color: Colors.green),
                        SizedBox(width: 8),
                        Flexible(child: Text("ไฟล์ที่เลือก: **$fileName**", style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ],
                ),

              SizedBox(height: 20),

              ElevatedButton(
                // ปุ่มจะใช้งานได้เมื่อมีไฟล์, Bytes, และ historyId
                onPressed: slipFile == null || loading || historyId == null ? null : uploadSlip, 
                child: loading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text("ยืนยันการเติมเงิน"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}