import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart'; // ตรวจสอบให้แน่ใจว่า import 'constants.dart' ถูกต้อง

class ConfigService {
  static String baseUrl = "";
  // 🌟 ตัวแปรสำหรับเก็บเวอร์ชันของ Config ปัจจุบันที่แอปฯ กำลังใช้
  static int currentConfigVersion = 0; 
  
  // URL สำหรับดึง Config จาก GitHub
  static const String CONFIG_URL = 
      "https://raw.githubusercontent.com/THEBLACKDAN/GhostBee_flutter/refs/heads/main/ghostbee_flutter/config.json";

  // ✨ NEW: เมธอดสำหรับเซ็ตค่า Base URL อย่างเป็นทางการ
  static void setBaseUrl(String url, int version) {
    String loadedUrl = url;
    if (loadedUrl.endsWith('/')) {
      loadedUrl = loadedUrl.substring(0, loadedUrl.length - 1);
    } 
    
    baseUrl = loadedUrl;
    currentConfigVersion = version;
    AppConstants.baseUrl = baseUrl; // เซ็ตค่าให้ AppConstants ทันที
    print("Base URL set to: $baseUrl (v$version)");
  }

  // ✨ NEW: เมธอดที่ดึงและคืนค่า Config ล่าสุดจาก Server เท่านั้น (ไม่ได้ตั้งค่า)
  static Future<Map<String, dynamic>?> fetchLatestConfig() async {
    try {
      final response = await http.get(Uri.parse(CONFIG_URL));

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        return jsonData;
      }
      return null;
    } catch (e) {
      print("Error fetching latest config: $e");
      return null;
    }
  }
}