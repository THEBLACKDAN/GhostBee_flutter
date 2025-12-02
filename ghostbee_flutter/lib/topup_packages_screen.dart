import 'package:flutter/material.dart';
import 'upload_slip_screen.dart';
import './models/user.dart';

class TopupPackagesScreen extends StatelessWidget {
  final User currentUser;
  TopupPackagesScreen({required this.currentUser});

  final List<int> packages = [50, 100, 300, 500];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("เติมเงิน"),
        elevation: 0,
        backgroundColor: Colors.deepPurple,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade100],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: EdgeInsets.all(16),
          children: packages
              .map((amount) => _buildPackageCard(context, amount))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPackageCard(BuildContext context, int amount) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UploadSlipScreen(
              amount: amount,
              currentUser: currentUser,
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            )
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.amber.shade600,
              child: Icon(Icons.monetization_on, color: Colors.white, size: 35),
            ),
            SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$amount บาท",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "= $amount Coins",
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}
