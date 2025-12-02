// payment_controller.js
const express = require('express');
const router = express.Router();

// ⚠️ (Mockup) ดึงข้อมูลสินค้าจากตาราง Products (ในทางปฏิบัติควรดึงจาก DB จริง)
const getProductInfo = (productId) => {
    // ⚠️ ID: 1, 2, 3 ควรดึงจากตาราง Products
    const products = {
        1: { product_name: 'Coin Pack S', product_type: 'COIN_PACKAGE', price_baht: 50.00, coins_granted: 500 },
        2: { product_name: 'VIP 30 Days', product_type: 'VIP_MEMBERSHIP', price_coins: 500, duration_days: 30 },
    };
    return products[productId];
};

// 🔑 Export ฟังก์ชันที่รับ db และ io (สำหรับใช้งานใน server.js)
module.exports = (db, io) => {
    
    // 🆕 API 1: Webhook Endpoint (รับการแจ้งเตือนจาก Payment Gateway) - เติมเหรียญ
    router.post('/webhook/topup', (req, res) => {
        const { user_id, product_id, payment_status, ref_id } = req.body; 

        if (payment_status !== 'SUCCESS') {
            return res.status(200).json({ received: true, message: 'Payment not successful' });
        }

        const packageInfo = getProductInfo(product_id);
        if (!packageInfo || packageInfo.product_type !== 'COIN_PACKAGE') {
            return res.status(400).json({ received: false, message: 'Invalid product ID or type' });
        }
        
        // 1. ดึงยอดเหรียญปัจจุบันของผู้ใช้
        db.query('SELECT coin_balance FROM users WHERE id = ?', [user_id], (err, userResults) => {
            if (err || userResults.length === 0) {
                console.error("Top-up Failed: User not found or DB error.");
                return res.status(500).json({ received: false, message: 'Internal server error' });
            }
            
            const currentBalance = userResults[0].coin_balance;
            const newBalance = currentBalance + packageInfo.coins_granted;

            // 2. อัปเดตยอดเหรียญในตาราง Users
            db.query('UPDATE users SET coin_balance = ? WHERE id = ?', [newBalance, user_id], (err) => {
                if (err) {
                    console.error("Top-up Failed: Error updating balance.");
                    return res.status(500).json({ received: false, message: 'Error updating balance' });
                }

                // 3. บันทึกรายการลงในตาราง Coin_Transactions
                const transactionSql = `INSERT INTO coin_transactions (user_id, transaction_type, amount, current_balance, description, ref_id) 
                     VALUES (?, ?, ?, ?, ?, ?)`;
                db.query(transactionSql, [
                    user_id, 
                    'TOP_UP', 
                    packageInfo.coins_granted, 
                    newBalance, 
                    `Top-up: ${packageInfo.product_name}`, 
                    ref_id 
                ], (err) => {
                    if (err) console.error("Warning: Could not save transaction record!", err);
                    
                    // 4. แจ้งเตือนแอปฯ (ผ่าน Socket.IO)
                    io.to(user_id.toString()).emit('receiveBalanceUpdate', { 
                        new_balance: newBalance,
                        is_vip: false, 
                        vip_expiry_date: null
                    });

                    res.status(200).json({ received: true, new_balance: newBalance });
                });
            });
        });
    });


    // 🆕 API 2: API สำหรับซื้อ VIP ด้วยเหรียญ
    router.post('/purchase/vip', (req, res) => {
        const { user_id, product_id } = req.body;
        
        const productInfo = getProductInfo(product_id);
        if (!productInfo || productInfo.product_type !== 'VIP_MEMBERSHIP') {
            return res.status(400).json({ message: 'Invalid product ID or type for VIP purchase' });
        }
        
        const VIP_COST = productInfo.price_coins;
        const DURATION_DAYS = productInfo.duration_days;
        
        // 1. ดึงยอดคงเหลือและวันหมดอายุ VIP ปัจจุบัน
        db.query('SELECT coin_balance, vip_expiry_date FROM users WHERE id = ?', [user_id], (err, userResults) => {
            if (err || userResults.length === 0) {
                return res.status(500).json({ message: 'Database error or user not found' });
            }
            
            const user = userResults[0];
            if (user.coin_balance < VIP_COST) {
                return res.status(400).json({ message: 'Insufficient coins' });
            }

            const newBalance = user.coin_balance - VIP_COST;
            
            // 2. คำนวณวันหมดอายุใหม่
            let expiryDate = new Date();
            if (user.vip_expiry_date) {
                const currentExpiry = new Date(user.vip_expiry_date);
                if (currentExpiry.getTime() > new Date().getTime()) { 
                     expiryDate = currentExpiry;
                }
            }
            expiryDate.setDate(expiryDate.getDate() + DURATION_DAYS);
            const sqlExpiryDate = expiryDate.toISOString().slice(0, 19).replace('T', ' ');

            // 3. อัปเดต Users (หักเหรียญ + ให้สิทธิ์ VIP)
            const updateSql = `UPDATE users SET coin_balance = ?, is_vip = TRUE, vip_expiry_date = ? WHERE id = ?`;
            db.query(updateSql, [newBalance, sqlExpiryDate, user_id], (err) => {
                if (err) {
                     console.error("Purchase Failed: Error updating balance/VIP status.");
                     return res.status(500).json({ message: 'Error processing purchase' });
                }

                // 4. บันทึกรายการ Transaction (หัก)
                const transactionSql = `INSERT INTO coin_transactions (user_id, transaction_type, amount, current_balance, description) 
                     VALUES (?, ?, ?, ?, ?)`;
                db.query(transactionSql,
                    [user_id, 'PURCHASE', -VIP_COST, newBalance, `Purchase: ${productInfo.product_name}`], (err) => {
                        if (err) console.error("Warning: Could not save purchase transaction record!", err);
                        
                        // 5. แจ้งเตือนแอปฯ (Socket.IO)
                        io.to(user_id.toString()).emit('receiveBalanceUpdate', { 
                            new_balance: newBalance, 
                            is_vip: true,
                            vip_expiry_date: expiryDate.toISOString()
                        });

                        res.status(200).json({ 
                            message: 'VIP activated', 
                            new_balance: newBalance, 
                            expiry_date: expiryDate.toISOString() 
                        });
                });
            });
        });
    });

    // 🆕 API 3: API สำหรับดึงยอดเหรียญและสถานะ VIP
    router.get('/user/balance/:user_id', (req, res) => {
        const { user_id } = req.params;
        const sql = 'SELECT coin_balance, is_vip, vip_expiry_date FROM users WHERE id = ?';
        db.query(sql, [user_id], (err, results) => {
            if (err) return res.status(500).json({ message: 'Database error' });
            if (results.length === 0) {
                return res.status(404).json({ message: 'User not found' });
            }
            res.status(200).json(results[0]);
        });
    });

    return router;
};