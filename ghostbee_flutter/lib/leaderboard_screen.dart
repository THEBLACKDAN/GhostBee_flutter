// leaderboard_screen.dart
import 'package:flutter/material.dart';

// Class สำหรับเก็บข้อมูลผู้เล่น
class Player {
  final String name;
  final int score;
  final String avatarUrl;

  Player({
    required this.name,
    required this.score,
    required this.avatarUrl,
  });
}

class LeaderboardScreen extends StatefulWidget {
  // เปลี่ยนชื่อจาก LeaderboardPage เป็น LeaderboardScreen เพื่อความชัดเจน
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  // Mock Data (สามารถดึงจาก API จริงในอนาคต)
  final List<Player> players = [
    Player(name: "David", score: 2500, avatarUrl: "https://i.pravatar.cc/150?u=1"),
    Player(name: "Sarah", score: 2350, avatarUrl: "https://i.pravatar.cc/150?u=2"),
    Player(name: "Michael", score: 2100, avatarUrl: "https://i.pravatar.cc/150?u=3"),
    Player(name: "Emily", score: 1950, avatarUrl: "https://i.pravatar.cc/150?u=4"),
    Player(name: "James", score: 1800, avatarUrl: "https://i.pravatar.cc/150?u=5"),
    Player(name: "Jessica", score: 1750, avatarUrl: "https://i.pravatar.cc/150?u=6"),
    Player(name: "Daniel", score: 1600, avatarUrl: "https://i.pravatar.cc/150?u=7"),
    Player(name: "Laura", score: 1550, avatarUrl: "https://i.pravatar.cc/150?u=8"),
    Player(name: "Kevin", score: 1400, avatarUrl: "https://i.pravatar.cc/150?u=9"),
    Player(name: "Anna", score: 1200, avatarUrl: "https://i.pravatar.cc/150?u=10"),
  ];

  @override
  Widget build(BuildContext context) {
    // Sort players by score descending
    players.sort((a, b) => b.score.compareTo(a.score));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Leaderboard", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        // ใช้ AppBar ของ BeeTalk App (สีเหลืองอำพัน)
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor, 
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
      ),
      body: Column(
        children: [
          // Top 3 Section
          Container(
            padding: const EdgeInsets.only(bottom: 20, top: 10), // เพิ่ม padding ด้านบนเล็กน้อย
            // ใช้สีพื้นหลังที่เข้ากับ Theme หลัก
            color: Theme.of(context).appBarTheme.backgroundColor, 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (players.length > 1) _buildTopThreeItem(players[1], 2), // Silver
                if (players.isNotEmpty) _buildTopThreeItem(players[0], 1), // Gold
                if (players.length > 2) _buildTopThreeItem(players[2], 3), // Bronze
              ],
            ),
          ),
          
          // Remaining List
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -5),
                  )
                ],
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: players.length > 3 ? players.length - 3 : 0, // ป้องกัน Index Out of Bounds
                itemBuilder: (context, index) {
                  final player = players[index + 3];
                  return _buildListItem(player, index + 4);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopThreeItem(Player player, int rank) {
    double size = rank == 1 ? 100 : 80;
    Color borderColor = rank == 1 
        ? Colors.amber // Gold
        : rank == 2 ? Colors.grey[400]! : Colors.brown[300]!; // Silver/Bronze

    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: borderColor.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: CircleAvatar(
                radius: size / 2,
                backgroundImage: NetworkImage(player.avatarUrl),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: borderColor,
              ),
              child: Text(
                "$rank",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          player.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        Text(
          "${player.score}",
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildListItem(Player player, int rank) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              "$rank",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 15),
          CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(player.avatarUrl),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              player.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Text(
            "${player.score} pts",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFC107), // ใช้สีเหลืองอำพันของ App
            ),
          ),
        ],
      ),
    );
  }
}