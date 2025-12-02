import 'dart:convert';
import 'package:http/http.dart' as http;

class ConfigService {
  static String baseUrl = "";

  static Future<void> load() async {
    final url =
        "https://raw.githubusercontent.com/THEBLACKDAN/GhostBee_flutter/refs/heads/main/ghostbee_flutter/config.json";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      String loadedUrl = jsonData["api_base_url"];
      
      // ✨ เพิ่ม Logic ตัด / ท้าย URL
      if (loadedUrl.endsWith('/')) {
        loadedUrl = loadedUrl.substring(0, loadedUrl.length - 1);
      }
      
      baseUrl = loadedUrl; // เก็บค่าที่ถูกตัดแล้ว
      print("Loaded API URL: $baseUrl");
    } else {
      throw Exception("Failed to load config");
    }
  }
}