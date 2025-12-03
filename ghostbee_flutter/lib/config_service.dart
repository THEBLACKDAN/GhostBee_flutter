// config_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // <<< NEW IMPORT
import 'constants.dart'; // ต้องมั่นใจว่าไฟล์นี้มี AppConstants.baseUrl

class ConfigService {
  static String baseUrl = "";
  // เวอร์ชันปัจจุบันที่แอปฯ กำลังใช้ (โหลดมาจาก SharedPrefs หรือ Default 0)
  static int currentConfigVersion = 0; 
  
  static const String CONFIG_URL = 
      "https://raw.githubusercontent.com/THEBLACKDAN/GhostBee_flutter/refs/heads/main/ghostbee_flutter/config.json";
  
  // Keys สำหรับ SharedPreferences
  static const String _KEY_BASE_URL = 'config_base_url';
  static const String _KEY_CONFIG_VERSION = 'config_version';

  // ✨ NEW: เมธอดสำหรับโหลด Config ที่บันทึกไว้
  static Future<void> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    // โหลดค่าจาก SharedPreferences
    final savedUrl = prefs.getString(_KEY_BASE_URL);
    final savedVersion = prefs.getInt(_KEY_CONFIG_VERSION);

    // ใช้ค่าที่โหลดมาเป็นค่าเริ่มต้น
    if (savedUrl != null && savedVersion != null) {
      // ไม่ต้องบันทึกซ้ำ แค่ตั้งค่า Static Variables
      _applyBaseUrl(savedUrl, savedVersion); 
      print("Loaded SAVED config: $baseUrl (v$currentConfigVersion)");
    } else {
      // ถ้าไม่มีค่าบันทึกไว้ ให้ใช้ค่าว่าง (0)
      baseUrl = "";
      currentConfigVersion = 0;
      AppConstants.baseUrl = baseUrl;
      print("No saved config found. Using default version 0.");
    }
  }

  // ✨ NEW: เมธอดสำหรับเซ็ตค่า Base URL และบันทึกลง SharedPreferences
  static Future<void> setBaseUrl(String url, int version) async {
    final prefs = await SharedPreferences.getInstance();
    
    _applyBaseUrl(url, version);
    
    // บันทึกค่าใหม่ลง SharedPreferences
    await prefs.setString(_KEY_BASE_URL, baseUrl);
    await prefs.setInt(_KEY_CONFIG_VERSION, version);
    print("Base URL set and SAVED: $baseUrl (v$version)");
  }
  
  // เมธอดสำหรับเซ็ตค่า Static Variables ภายใน Class
  static void _applyBaseUrl(String url, int version) {
    String loadedUrl = url;
    if (loadedUrl.endsWith('/')) {
      loadedUrl = loadedUrl.substring(0, loadedUrl.length - 1);
    } 
    
    baseUrl = loadedUrl;
    currentConfigVersion = version;
    AppConstants.baseUrl = baseUrl; 
  }


  // ✨ fetchLatestConfig: ดึง Config ล่าสุดจาก Server เท่านั้น (ไม่ได้ตั้งค่า)
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