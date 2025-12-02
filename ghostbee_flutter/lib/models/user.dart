class User {
  final int id;
  final String username;
  
  String displayName; // ⚠️ 1. เอา final ออก
  final String gender;
  String image;       // ⚠️ 2. เอา final ออก
  
  int coinBalance;    
  bool isVip;         // ⚠️ 3. เอา final ออก (ถ้ายังไม่ได้เอาออก)

  User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.gender,
    required this.image,
    this.coinBalance = 0,
    this.isVip = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      displayName: json['display_name'], // DB ส่งมาเป็น display_name
      gender: json['gender'],
      image: json['image'] ?? 'https://i.pravatar.cc/150?img=${json['id']}',
      
      // 👇👇👇 2. จุดสำคัญอยู่ตรงนี้! ต้อง Map ชื่อให้ตรงกับ Database 👇👇👇
      coinBalance: json['coin_balance'] ?? 0, 
      // ☝️☝️☝️ ถ้าใน DB ชื่อ coin_balance ต้องเขียนตรงนี้ให้เหมือนเป๊ะๆ
      
      isVip: (json['is_vip'] == 1 || json['is_vip'] == true),
    );
  }
}