//server.js
const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const bodyParser = require('body-parser');
const http = require('http'); 
const { Server } = require("socket.io"); 
const fs = require('fs');
const path = require('path');



// require('dotenv').config(); // Uncomment ถ้าใช้ .env


// --- CONFIGURATION MANAGEMENT: อ่านและถอดรหัส DB ---
const PORT = process.env.PORT || 3000;
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || '*'; 
const DB_CONFIG_FILE = 'config_db.txt'; 
const CLUB_DURATION_MINUTES = 15; // กำหนดระยะเวลา Club Room

// 🔐 ฟังก์ชันถอดรหัส Base64
function decodeBase64(b64String) {
    return Buffer.from(b64String.trim(), 'base64').toString('utf8');
}

// 🔍 ฟังก์ชันแยก URI ออกเป็น Object Config
function parseMysqlUri(uri) {
    const match = uri.match(/^mysql:\/\/([^:]+):([^@]+)@([^:]+):(\d+)\/(\w+)/);
    if (!match) {
        throw new Error('Invalid MySQL URI format. Expected: mysql://user:pass@host:port/database');
    }
    const [, user, password, host, port, database] = match;
    return { host, user, password, database, port: parseInt(port, 10) };
}

// 📂 อ่านไฟล์และเตรียมการเชื่อมต่อ
let db;
let dbConfig;
try {
    const b64Content = fs.readFileSync(path.join(__dirname, DB_CONFIG_FILE), 'utf8');
    const connectionUri = decodeBase64(b64Content);
    dbConfig = parseMysqlUri(connectionUri);
    
    dbConfig.charset = 'utf8mb4';
    dbConfig.timezone = '+07:00';
    
    // --- 1. การเชื่อมต่อฐานข้อมูล ---
    db = mysql.createConnection(dbConfig);
    
    db.connect((err) => {
        if (err) {
            console.error('Error connecting to MySQL:', err);
            return;
        }
        console.log(`Connected to MySQL Database (${dbConfig.database})`);
        db.query('SET NAMES utf8mb4');
    });

} catch (e) {
    console.error(`FATAL: Failed to load database configuration from ${DB_CONFIG_FILE}:`, e.message);
    process.exit(1);
}

// --- SETUP EXPRESS & SOCKET.IO ---
const app = express();
app.use(cors({ origin: ALLOWED_ORIGIN })); 
app.use(bodyParser.json());

const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: ALLOWED_ORIGIN, 
        methods: ["GET", "POST", "PUT", "DELETE"]
    }
});

// ----------------------------------------------------
// 2. CLUB TIMER LOGIC (Database-Based)
// ----------------------------------------------------

// ⚠️ In-Memory map เพื่อเก็บ Timer Instance ที่กำลังทำงานอยู่
const clubTimers = new Map(); // clubId -> Timer Instance

// 🆕 Helper: Clean up Club and Notify (ใช้ตอน Club หมดอายุ หรือ ถูกปิด)
function _endClubRoom(clubId, reason) {
    // 1. Clear Timer ถ้ายังทำงานอยู่
    if (clubTimers.has(clubId)) {
        clearTimeout(clubTimers.get(clubId));
        clubTimers.delete(clubId);
    }
    
    console.log(`Club ${clubId} closing: ${reason}`);

    // 2. ส่งสัญญาณให้ Client ในห้องนี้ทั้งหมดรู้ว่าห้องปิดแล้ว
    // ⚠️ Client ใน club_room_screen.dart จะดักจับ Event 'receiveMessage'
    io.to(`club_${clubId}`).emit('receiveMessage', { 
        message: reason
    });

    // 3. ลบ Club ออกจาก Database
    db.query('DELETE FROM clubs WHERE id = ?', [clubId], (err) => {
        if (err) console.error("Error deleting expired club:", err);
    });
    // การลบใน clubs จะทำให้ club_members ถูกลบไปด้วยถ้าใช้ ON DELETE CASCADE
}

// 🆕 Helper: Start Timer
function startClubTimer(clubId, clubName) {
    const timer = setTimeout(() => {
        _endClubRoom(clubId, `Room ${clubName} has expired (${CLUB_DURATION_MINUTES} minutes limit).`);
    }, CLUB_DURATION_MINUTES * 60 * 1000); // 15 นาที
    
    clubTimers.set(clubId, timer);
}

// ----------------------------------------------------
// 3. SOCKET.IO LOGIC: การจัดการ Real-time Chat & Club
// ----------------------------------------------------

io.on('connection', (socket) => {
    console.log(`User connected: ${socket.id}`);

    let currentUserId = null; 
    let currentClubId = null;



    // 1. Client แจ้งว่า Login แล้ว (ส่ง ID มา) -> สร้างห้องแชทส่วนตัวให้ User
    socket.on('joinRoom', (userId) => {
        // ⚠️ Store userId ใน socket instance (ถ้าจำเป็นต้องใช้ใน disconnect)
        // socket.data.userId = userId;
        socket.join(userId.toString());
        console.log(`User ${userId} joined room ${userId}`);
    });

    // 2. Client ส่งข้อความใหม่ (Chat)
    socket.on('sendMessage', (data) => {
        const sql = 'INSERT INTO messages (sender_id, receiver_id, content) VALUES (?, ?, ?)';
        db.query(sql, [data.senderId, data.receiverId, data.content], (err, result) => {
            if (err) {
                console.error("DB error saving message:", err);
                return;
            }
            
            const newMessage = {
                id: result.insertId,
                sender_id: data.senderId,
                receiver_id: data.receiverId,
                content: data.content,
                created_at: new Date().toISOString(),
            };

            io.to(data.receiverId.toString()).emit('receiveMessage', newMessage);
            io.to(data.senderId.toString()).emit('receiveMessage', newMessage);
        });
    });

    // 3. เมื่อ Client เริ่มพิมพ์ (Typing)
    socket.on('typing', async (data) => {
        // A. ส่งสถานะ Typing ให้ฝั่งตรงข้ามเห็น (UI)
        io.to(data.receiverId.toString()).emit('typingStatus', {
            userId: data.senderId,
            status: 'typing...',
        });

        // B. ✨ NEW: สั่ง Mark as Read ทันทีที่พิมพ์
        // เพราะถ้าเขากำลังพิมพ์ตอบ แสดงว่าเขาต้องเปิดหน้าแชทอ่านข้อความเราแล้วแน่นอน
        try {
            await db.promise().query(
                'UPDATE messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
                [data.receiverId, data.senderId] // กลับด้านกัน: เราอ่านข้อความของคนที่เรากำลังจะพิมพ์หา
            );

            // แจ้งกลับไปหาเจ้าของข้อความ (receiverId) ว่า "ข้อความถูกอ่านแล้ว" (ขึ้น Seen)
            io.to(data.receiverId.toString()).emit('messagesRead', {
                readerId: data.senderId, // คนอ่าน = คนที่พิมพ์อยู่
                senderId: data.receiverId 
            });

        } catch (err) {
            console.error("Error auto-read on typing:", err);
        }
    });

    // 4. เมื่อ Client หยุดพิมพ์ (Stop Typing)
    socket.on('stopTyping', (data) => {
        io.to(data.receiverId.toString()).emit('typingStatus', {
            userId: data.senderId,
            status: '', // เมื่อหยุดพิมพ์ ให้สถานะหายไป
        });
    });
    
    // 5. 🆕 Club: User Join Club Room (ใช้สำหรับนับคนและส่ง Event ปิดห้อง)
    socket.on('joinClub', (data) => {
        // รับเป็น Object { clubId, userId } จาก Client
        const { clubId, userId } = data; 
        
        currentClubId = clubId;
        currentUserId = userId;
        socket.join(`club_${clubId}`);
        
        // 1. เพิ่มคนเข้าตาราง club_members
        db.query(
            // ⚠️ [FIX]: ใช้ role เป็น listener ตั้งแต่แรก (Owner ถูกใส่เป็น admin ไปตั้งแต่ตอนสร้างแล้ว)
            'INSERT IGNORE INTO club_members (club_id, member_id, role) VALUES (?, ?, ?)', 
            [clubId, userId, 'listener'], 
            (err) => {
                // 2. แจ้งจำนวนคนใหม่ให้ทุกคนรู้
                broadcastMemberCount(clubId);
            }
        );
    });

    // 👉 แก้ไข: leaveClub (ออกห้อง)
    socket.on('leaveClub', (clubId) => {
        socket.leave(`club_${clubId}`);
        if (currentUserId) {
             // 1. ลบคนออกจากตาราง
            db.query(
                'DELETE FROM club_members WHERE club_id = ? AND member_id = ?', 
                [clubId, currentUserId], 
                (err) => {
                    // 2. แจ้งจำนวนคนใหม่
                    broadcastMemberCount(clubId);
                }
            );
        }
        currentClubId = null; 
    });

    // 👉 แก้ไข: disconnect (เน็ตหลุด/ปิดแอป)
    socket.on('disconnect', () => {
        // ถ้าตอนหลุด เขาอยู่ในห้อง Club ให้ลบชื่อออกด้วย
        if (currentClubId && currentUserId) {
            db.query(
                'DELETE FROM club_members WHERE club_id = ? AND member_id = ?', 
                [currentClubId, currentUserId], 
                (err) => {
                    broadcastMemberCount(currentClubId);
                }
            );
        }
    });
    
    // 🆕 [เพิ่ม]: รับ Event อัปเดต Stage จาก Client และส่งต่อให้ทุกคนในห้อง
    socket.on('updateStage', (data) => {
        const { clubId, stageSlots } = data;
        
        // ส่ง Stage Slots ใหม่ไปให้ Client ทุกคนในห้อง (ยกเว้นตัวคนส่งเอง)
        socket.to(`club_${clubId}`).emit('receiveMessage', { 
            stageSlots: stageSlots
        });
    });

    
});



// ----------------------------------------------------
// 4. API ENDPOINTS (EXPRESS)
// ----------------------------------------------------

// --- AUTH & USER APIs ---

app.post('/register', (req, res) => {
    const { username, password, display_name, gender } = req.body;
    const sql = 'INSERT INTO users (username, password, display_name, gender) VALUES (?, ?, ?, ?)';
    db.query(sql, [username, password, display_name, gender], (err, result) => {
        if (err) {
            if (err.code === 'ER_DUP_ENTRY') return res.status(409).json({ message: 'Username already exists' });
            return res.status(500).json({ message: 'Database error' });
        }
        res.status(201).json({ message: 'User registered successfully', userId: result.insertId });
    });
});

app.post('/login', (req, res) => {
    const { username, password } = req.body;
    const sql = 'SELECT * FROM users WHERE username = ? AND password = ?';
    db.query(sql, [username, password], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        if (results.length > 0) {
            res.json({ message: 'Login successful', user: results[0] });
        } else {
            res.status(401).json({ message: 'Invalid credentials' });
        }
    });
});

// API: ดึงข้อมูลผู้ใช้จาก ID (ใช้สำหรับ Auto-Login/Profile)
app.get('/user/:userId', async (req, res) => {
    const userId = req.params.userId;

    try {
        // 1. ดึงข้อมูลมาก่อน
        const [users] = await db.promise().query('SELECT * FROM users WHERE id = ?', [userId]);
        if (users.length === 0) return res.status(404).json({ message: 'User not found' });
        
        let user = users[0];

        // -----------------------------------------------------
        // 🕒 LOGIC เช็ควันหมดอายุ (เพิ่มตรงนี้)
        // -----------------------------------------------------
        if (user.is_vip === 1 && user.vip_expire_at) {
            const expireDate = new Date(user.vip_expire_at);
            const now = new Date();

            // ถ้าวันหมดอายุ น้อยกว่า เวลาปัจจุบัน (แปลว่าหมดอายุแล้ว)
            if (expireDate < now) {
                // 1. อัปเดตใน Database ให้ is_vip = 0
                await db.promise().query('UPDATE users SET is_vip = 0, vip_expire_at = NULL WHERE id = ?', [userId]);
                
                // 2. อัปเดตตัวแปร user เพื่อส่งกลับไปให้แอป (User จะเห็นทันทีว่าหลุด VIP แล้ว)
                user.is_vip = 0;
                user.vip_expire_at = null;
                
                console.log(`User ${userId} VIP expired. Downgraded.`);
            }
        }
        // -----------------------------------------------------

        res.json({ user: user });

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: 'Database error' });
    }
});

// API ดึงสถิติ User (Posts & Friends)
app.get('/user/stats/:id', async (req, res) => {
    const userId = req.params.id;

    try {
        // 1. นับจำนวนโพสต์ (Posts)
        const [postResult] = await db.promise().query(
            'SELECT COUNT(*) as count FROM posts WHERE user_id = ?', 
            [userId]
        );
        const postCount = postResult[0].count;

        // 2. นับจำนวนเพื่อน (Friends)
        // (นับคนที่ status = 'accepted' โดยที่เราอาจจะเป็นคนขอ (sender) หรือคนถูกขอ (receiver) ก็ได้)
        const [friendResult] = await db.promise().query(
            `SELECT COUNT(*) as count FROM friend_requests 
             WHERE (sender_id = ? OR receiver_id = ?) AND status = 'accepted'`,
            [userId, userId]
        );
        const friendCount = friendResult[0].count;

        // ส่งค่ากลับไป
        res.json({ 
            posts: postCount, 
            friends: friendCount 
        });

    } catch (err) {
        console.error("Error fetching stats:", err);
        res.status(500).json({ message: 'Server error', posts: 0, friends: 0 });
    }
});

// API: ดึงสถิติผู้ใช้ (Posts และ Friends)
app.get('/user/stats/:userId', (req, res) => {
    const userId = req.params.userId;

    db.query('SELECT COUNT(*) AS count FROM posts WHERE user_id = ?', [userId], (err, postResults) => {
        if (err) return res.status(500).json({ message: 'Error fetching post count' });
        const postCount = postResults[0].count;

        const friendSql = `
            SELECT COUNT(*) AS count 
            FROM friend_requests 
            WHERE (sender_id = ? OR receiver_id = ?) AND status = 'accepted'
        `;

        db.query(friendSql, [userId, userId], (err, friendResults) => {
            if (err) return res.status(500).json({ message: 'Error fetching friend count' });
            const friendsCount = friendResults[0].count;

            res.json({ posts: postCount, friends: friendsCount });
        });
    });
});

app.put('/user/:id', async (req, res) => {
    const userId = req.params.id;
    // ✨ NEW: เพิ่ม bio เข้าไปใน Destructuring
    const { display_name, image, bio } = req.body; 

    try {
        // 1. เช็คก่อนว่าเป็น VIP ไหม (เพื่อความปลอดภัยกันคนยิง API ตรงๆ)
        const [users] = await db.promise().query('SELECT is_vip FROM users WHERE id = ?', [userId]);
        if (users.length === 0) return res.status(404).json({ message: 'User not found' });
        
        const isVip = (users[0].is_vip === 1);

        // 2. เตรียมข้อมูลอัปเดต: ต้องใส่ bio เข้าไป
        // ✨ แก้ไข: เริ่มต้น SQL ด้วย display_name และ bio
        let sql = 'UPDATE users SET display_name = ?, bio = ?'; 
        let params = [display_name, bio]; // ✨ เพิ่ม bio ใน parameters

        // 3. ถ้าเป็น VIP ถึงจะยอมให้อัปเดต image
        if (isVip && image) {
            sql += ', image = ?';
            params.push(image);
        } else if (!isVip && image) {
             // 💡 ถ้าไม่ใช่ VIP แต่พยายามส่ง image มา, ให้ clear image เป็น NULL/empty string แทนการอัพเดท
             sql += ', image = NULL';
        }

        sql += ' WHERE id = ?';
        params.push(userId);

        await db.promise().query(sql, params);

        res.json({ message: 'Profile updated successfully' });

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: 'Server error' });
    }
});

// API: ดึงประวัติข้อความ
app.get('/messages/:userId1/:userId2', (req, res) => {
    const { userId1, userId2 } = req.params;
    const sql = `
        SELECT * FROM messages 
        WHERE (sender_id = ? AND receiver_id = ?) 
            OR (sender_id = ? AND receiver_id = ?)
        ORDER BY created_at ASC
    `;
    db.query(sql, [userId1, userId2, userId2, userId1], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.json(results);
    });
});

// server.js (ส่วนที่แก้ไขใน app.put('/messages/mark-read'))

app.put('/messages/mark-read', async (req, res) => {
    const { sender_id, receiver_id } = req.body; 
    
    try {
        await db.promise().query(
            'UPDATE messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
            [sender_id, receiver_id]
        );

        // ⚠️ แก้ไขตรงนี้: เติม .toString() เข้าไปครับ
        io.to(sender_id.toString()).emit('messagesRead', { 
            readerId: receiver_id,
            senderId: sender_id,
        });

        res.status(200).json({ message: 'Messages marked as read' });
    } catch (err) {
        console.error("Error marking messages as read:", err);
        res.status(500).json({ message: 'Server error' });
    }
});


// --- BOARD APIs ---

app.get('/posts', (req, res) => {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;

    const sql = `
        SELECT posts.*, users.display_name, users.gender 
        FROM posts 
        JOIN users ON posts.user_id = users.id 
        ORDER BY posts.created_at DESC
        LIMIT ? OFFSET ?`;
    
    db.query(sql, [limit, offset], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.json(results);
    });
});



app.post('/posts', async (req, res) => {
    const { user_id, content, is_boost } = req.body;
    
    // แปลงค่าให้ชัวร์
    const shouldBoost = (is_boost === true || is_boost === 1 || is_boost === 'true');
    const cost = 50; 
    const POST_LIMIT = 5; 

    try {
        // 1. ดึงข้อมูล User (เงิน + สถานะ VIP)
        const [users] = await db.promise().query(
            'SELECT coin_balance, is_vip FROM users WHERE id = ?', 
            [user_id]
        );

        if (users.length === 0) return res.status(404).json({ message: 'User not found' });
        
        const user = users[0];
        const isVip = (user.is_vip === 1 || user.is_vip === true);

        // =========================================================
        // 🚦 LOGIC ใหม่: เรียงลำดับความสำคัญ (Priority)
        // =========================================================

        // กรณีที่ 1: เป็น VIP -> ผ่านโลด
        if (isVip) {
            // ไม่ต้องทำอะไร ปล่อยผ่านไป Insert เลย
        } 
        // กรณีที่ 2: จ่ายเงิน (Boost) -> เช็คเงินอย่างเดียว (ไม่สน Limit)
        else if (shouldBoost) {
            if (user.coin_balance < cost) {
                return res.status(400).json({ message: 'Coin ไม่พอครับ (ต้องการ 50 Coins)' });
            }
            // ตัดเงิน
            await db.promise().query('UPDATE users SET coin_balance = coin_balance - ? WHERE id = ?', [cost, user_id]);
        } 
        // กรณีที่ 3: โพสต์ฟรี -> ต้องเช็คโควต้า
        else {
            const [countResult] = await db.promise().query(
                'SELECT COUNT(*) as count FROM posts WHERE user_id = ? AND DATE(created_at) = CURDATE()',
                [user_id]
            );
            const postsToday = countResult[0].count;

            if (postsToday >= POST_LIMIT) {
                return res.status(403).json({ 
                    message: `โควต้าฟรีหมดแล้ว! (ครบ 5 โพสต์) \nคุณสามารถจ่าย 50 Coins เพื่อโพสต์ต่อได้` 
                });
            }
        }
        // =========================================================

        // 3. บันทึกโพสต์ลง DB
        await db.promise().query(
            'INSERT INTO posts (user_id, content, created_at, is_boost) VALUES (?, ?, NOW(), ?)',
            [user_id, content, shouldBoost]
        );

        res.status(201).json({ message: 'Post created successfully' });

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: 'Server error: ' + err.message });
    }
});

app.delete('/posts/:id', (req, res) => {
    const postId = req.params.id;
    const sql = 'DELETE FROM posts WHERE id = ?';
    db.query(sql, [postId], (err, result) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.json({ message: 'Post deleted' });
    });
});

app.get('/comments/:postId', (req, res) => {
    const postId = req.params.postId;
    const sql = `
        SELECT comments.*, users.display_name 
        FROM comments 
        JOIN users ON comments.user_id = users.id 
        WHERE post_id = ? 
        ORDER BY comments.created_at ASC`;
        
    db.query(sql, [postId], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.json(results);
    });
});

app.post('/comments', (req, res) => {
    const { post_id, user_id, content } = req.body;
    const sql = 'INSERT INTO comments (post_id, user_id, content) VALUES (?, ?, ?)';
    db.query(sql, [post_id, user_id, content], (err, result) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.status(201).json({ message: 'Comment added' });
    });
});


// --- FRIEND APIs ---

app.post('/friend-request', (req, res) => {
    const { sender_id, receiver_id } = req.body;

    if (sender_id == receiver_id) return res.status(400).json({ message: "Cannot add yourself" });

    const checkSql = `
        SELECT * FROM friend_requests 
        WHERE (sender_id = ? AND receiver_id = ?) 
            OR (sender_id = ? AND receiver_id = ?)
    `;

    db.query(checkSql, [sender_id, receiver_id, receiver_id, sender_id], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });

        if (results.length > 0) {
            const status = results[0].status;
            if (status === 'accepted') return res.status(409).json({ message: "Already friends" });
            if (status === 'pending') return res.status(409).json({ message: "Request already sent" });
        }

        const insertSql = 'INSERT INTO friend_requests (sender_id, receiver_id) VALUES (?, ?)';
        db.query(insertSql, [sender_id, receiver_id], (err, result) => {
            if (err) return res.status(500).json({ message: 'Database error' });
            res.status(201).json({ message: 'Friend request sent' });
        });
    });
});

app.get('/friend-requests/:userId', (req, res) => {
    const userId = req.params.userId;
    const sql = `
        SELECT fr.id as request_id, u.id as sender_id, u.display_name, u.gender, fr.created_at
        FROM friend_requests fr
        JOIN users u ON fr.sender_id = u.id
        WHERE fr.receiver_id = ? AND fr.status = 'pending'
        ORDER BY fr.created_at DESC
    `;
    db.query(sql, [userId], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.json(results);
    });
});

app.put('/respond-request', (req, res) => {
    const { request_id, action } = req.body; 

    if (!['accepted', 'rejected'].includes(action)) return res.status(400).json({ message: "Invalid action" });

    const sql = 'UPDATE friend_requests SET status = ? WHERE id = ?';
    db.query(sql, [action, request_id], (err, result) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        res.json({ message: `Request ${action}` });
    });
});

// server.js

// API ดึงรายชื่อเพื่อน (พร้อมจำนวนข้อความที่ยังไม่อ่าน)
app.get('/friends/:userId', async (req, res) => {
    const userId = req.params.userId;

    try {
        // Query นี้จะดึงข้อมูลเพื่อน + นับ unread_count มาให้เลย
        const sql = `
            SELECT 
                u.id, 
                u.display_name, 
                u.image, 
                u.gender, 
                u.is_vip, 
                u.vip_expire_at,
                (SELECT COUNT(*) 
                 FROM messages m 
                 WHERE m.sender_id = u.id 
                   AND m.receiver_id = ? 
                   AND m.is_read = 0
                ) AS unread_count
            FROM users u
            JOIN friend_requests fr 
              ON (fr.sender_id = u.id OR fr.receiver_id = u.id)
            WHERE (fr.sender_id = ? OR fr.receiver_id = ?)
              AND fr.status = 'accepted'
              AND u.id != ?
        `;

        // Parameter ที่ต้องส่งเข้าไป (userId ใส่ 4 ที่ตามเครื่องหมาย ?)
        const [friends] = await db.promise().query(sql, [userId, userId, userId, userId]);
        
        res.json(friends);

    } catch (err) {
        console.error("Error fetching friends:", err);
        res.status(500).json({ message: 'Server error' });
    }
});


// ----------------------------------------------------
// 5. CLUB APIs (Real/DB-Based)
// ----------------------------------------------------

// 🆕 API 1: Get All Active Clubs
app.get('/clubs', (req, res) => {
    const sql = `
        SELECT 
            c.id, c.name, c.creator_id AS ownerId, c.expires_at, 
            COUNT(cm.member_id) AS members
        FROM clubs c
        LEFT JOIN club_members cm ON c.id = cm.club_id
        WHERE c.status = 'active' AND c.expires_at > NOW()
        GROUP BY c.id
        ORDER BY c.created_at DESC
    `;
    db.query(sql, (err, results) => {
        if (err) {
            console.error("Error fetching clubs:", err);
            return res.status(500).json({ message: 'Database error' });
        }
        // แปลง ownerId เป็น number
        const clubs = results.map(club => ({
            ...club,
            ownerId: parseInt(club.ownerId),
            members: parseInt(club.members),
        }));
        return res.json({ clubs });
    });
});

// 🆕 API 2: Create Club (POST)
app.post('/clubs', (req, res) => {
    const { clubName, ownerId } = req.body;
    if (!clubName || !ownerId) return res.status(400).json({ error: 'clubName and ownerId are required.' });

    // 1. คำนวณเวลาหมดอายุ (15 นาทีจากตอนนี้)
    const expiresAt = new Date();
    expiresAt.setMinutes(expiresAt.getMinutes() + CLUB_DURATION_MINUTES);
    
    // 2. บันทึก Club ลง Database
    const clubSql = 'INSERT INTO clubs (name, creator_id, expires_at) VALUES (?, ?, ?)';
    db.query(clubSql, [clubName, ownerId, expiresAt], (err, result) => {
        if (err) {
            console.error(err);
            return res.status(500).json({ message: 'Database error during club creation' });
        }

        const newClubId = result.insertId;

        // 3. เพิ่มผู้สร้างเป็น Admin/Speaker ในตาราง club_members
        const memberSql = 'INSERT INTO club_members (club_id, member_id, role) VALUES (?, ?, ?)';
        db.query(memberSql, [newClubId, ownerId, 'admin'], (err) => {
             if (err) console.error("Error inserting creator as member:", err);
        });
        
        // 4. Start 15-minute Timer
        startClubTimer(newClubId, clubName);
        
        res.status(201).json({ 
            club: { 
                id: newClubId, 
                name: clubName,
                ownerId: ownerId,
                expires_at: expiresAt.toISOString() 
            } 
        });
    });
});

// 🆕 API 3: Get Single Club Details
app.get('/clubs/:clubId', (req, res) => {
    const clubId = req.params.clubId;
    const sql = 'SELECT * FROM clubs WHERE id = ? AND status = \'active\' AND expires_at > NOW()';
    db.query(sql, [clubId], (err, results) => {
        if (err) return res.status(500).json({ message: 'Database error' });
        if (results.length > 0) {
            res.json({ club: results[0] });
        } else {
            res.status(404).json({ message: 'Club not found or already closed.' });
        }
    });
});

// 🆕 API 4: Delete/End Club (DELETE)
app.delete('/clubs/:clubId', (req, res) => {
    const clubId = parseInt(req.params.clubId);
    
    // หาชื่อห้องก่อน (เพื่อเอาไปใส่ข้อความแจ้งเตือน)
    db.query('SELECT name FROM clubs WHERE id = ?', [clubId], (err, results) => {
        if (err || results.length === 0) {
            return res.status(404).json({ error: 'Club not found' });
        }
        const clubName = results[0].name;

        // ✅ เรียกฟังก์ชันนี้ เพื่อส่ง Socket บอกทุกคนให้เด้งออก
        _endClubRoom(clubId, `Club "${clubName}" was manually ended by the owner.`);
        
        return res.json({ message: 'Club ended successfully.' });
    });
});

// 🆕 API 5: Get All Members in a Club (Real-time Listener/Speaker List)
app.get('/clubs/:clubId/members', async (req, res) => {
    const clubId = req.params.clubId;

    // 1. ดึงข้อมูลสมาชิกจาก club_members และ JOIN กับ users เพื่อเอา display_name, image
    const sql = `
        SELECT 
            cm.member_id AS id, 
            cm.role, 
            u.display_name AS name, 
            u.image 
        FROM club_members cm
        JOIN users u ON cm.member_id = u.id
        WHERE cm.club_id = ?
    `;

    try {
        const [members] = await db.promise().query(sql, [clubId]);

        // Note: ในขั้นตอนต่อไป Client จะแบ่งแยกเองว่าใครอยู่ Stage (Speaker) หรือ Audience (Listener)
        res.json({ members });
    } catch (err) {
        console.error("Error fetching club members:", err);
        res.status(500).json({ message: 'Server error' });
    }
});


// ----------------------------------------------------
// ส่วนที่ 1: Helper Functions
// ----------------------------------------------------

// 🆕 ฟังก์ชัน: นับคนในห้อง แล้วส่งบอกทุกคน (Real-time Count)
function broadcastMemberCount(clubId) {
    db.query(
        'SELECT COUNT(member_id) AS members FROM club_members WHERE club_id = ?', 
        [clubId], 
        (err, results) => {
            if (err) return console.error(err);
            const memberCount = results[0].members;
            
            // ส่ง Event 'receiveMessage' พร้อมข้อมูล members
            io.to(`club_${clubId}`).emit('receiveMessage', { members: memberCount }); 
        }
    );
}

// server.js

// API เติมเงิน (Top Up)
app.post('/topup', async (req, res) => {
    const { user_id, amount } = req.body; // รับ ID และจำนวนเงินที่เติม

    try {
        // ใช้ logic บวกเงินเข้าไปในยอดเดิม
        await db.promise().query(
            'UPDATE users SET coin_balance = coin_balance + ? WHERE id = ?',
            [amount, user_id]
        );

        // ดึงยอดเงินล่าสุดส่งกลับไปให้แอปอัปเดตหน้าจอทันที
        const [users] = await db.promise().query('SELECT coin_balance FROM users WHERE id = ?', [user_id]);
        
        res.status(200).json({ 
            message: 'Topup successful', 
            new_balance: users[0].coin_balance 
        });

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: 'Server error' });
    }
});

// API ซื้อ VIP
app.post('/buy-vip', async (req, res) => {
    const { user_id, days, cost } = req.body;

    try {
        // 1. เช็คเงินก่อน
        const [users] = await db.promise().query('SELECT coin_balance, vip_expire_at FROM users WHERE id = ?', [user_id]);
        if (users.length === 0) return res.status(404).json({ message: 'User not found' });
        
        const user = users[0];
        if (user.coin_balance < cost) {
            return res.status(400).json({ message: 'Coin ไม่พอครับ' });
        }

        // 2. คำนวณวันหมดอายุใหม่
        let currentExpire = user.vip_expire_at ? new Date(user.vip_expire_at) : new Date();
        // ถ้า VIP เดิมยังไม่หมด ให้ต่อเวลาจากวันเดิม, ถ้าหมดแล้ว หรือไม่เคยเป็น ให้เริ่มนับจากวันนี้
        if (currentExpire < new Date()) {
            currentExpire = new Date();
        }
        
        // บวกจำนวนวันเพิ่ม
        currentExpire.setDate(currentExpire.getDate() + days);

        // 3. ตัดเงิน + อัปเดตสถานะ VIP + วันหมดอายุ
        await db.promise().query(
            'UPDATE users SET coin_balance = coin_balance - ?, is_vip = 1, vip_expire_at = ? WHERE id = ?',
            [cost, currentExpire, user_id]
        );

        // ส่งข้อมูลล่าสุดกลับไป
        const [updatedUser] = await db.promise().query('SELECT coin_balance, is_vip, vip_expire_at FROM users WHERE id = ?', [user_id]);

        res.json({ 
            message: `สมัคร VIP ${days} วัน สำเร็จ!`, 
            user: updatedUser[0] 
        });

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: 'Server error' });
    }
});

const paymentRoutes = require('./payment')(db); // <--- ต้องมีไฟล์ payment.js อยู่ใน Folder เดียวกัน
app.use('/payment', paymentRoutes);

// ----------------------------------------------------
// 6. START SERVER
// ----------------------------------------------------

server.listen(PORT, () => {
    console.log(`GhostBee Server and Socket.io listening at port ${PORT}`);
    console.log(`Allowed CORS Origin: ${ALLOWED_ORIGIN}`);
});