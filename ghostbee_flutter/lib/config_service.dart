import 'dart:convert';
import 'package:http/http.dart' as http;

class ConfigService {
  static String baseUrl = "";

  static Future<void> load() async {
    final url =
        "https://raw.githubusercontent.com/THEBLACKDAN/GhostBee_flutter/main/ghostbee_flutter/config.json";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      baseUrl = jsonData["api_base_url"];
      print("🔧 Loaded API URL: $baseUrl");
    } else {
      throw Exception("❌ Failed to load config.json");
    }
  }
}
