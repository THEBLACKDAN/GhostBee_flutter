// payment.js
const express = require('express');
const router = express.Router();
const multer = require('multer');
const Tesseract = require('tesseract.js');
const qrcode = require('qrcode');
const generatePayload = require('promptpay-qr'); 
const fs = require('fs');
const path = require('path');

// Helper: สร้างเลขเศษสตางค์ 2 หลักที่ไม่ซ้ำกัน (01-99)
// 🔥 กำหนดให้เป็น 76 เสมอสำหรับการทดสอบสลิป 50.76
function generateUniqueCents() {
    const cents = Math.floor(Math.random() * 99) + 1; // 1 ถึง 99
    return cents.toString().padStart(2, '0');
    // return '76';
}

module.exports = function(db) {

    const promptpayNumber = "0964016606";
    
    // Setup Multer
    const UPLOAD_DIR = path.join(__dirname, 'uploads');
    if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR);
    const upload = multer({ dest: UPLOAD_DIR });

    // ----------------------------------------------------
    // 3) ฟังก์ชันประมวลผล OCR และอัปเดตสถานะ (Async Background Task)
    // ----------------------------------------------------
    async function processSlip(historyId, user_id, slipPath) {
        let status = 'failed';
        let coins = 0;
        let ocr_text = 'N/A';
        let paidAmount = 0;
        let message = 'ตรวจสอบล้มเหลว';
        let referenceNo = null; // 🆕 ตัวแปรสำหรับเก็บเลขที่อ้างอิง

        try {
            // 1. ดึงยอดเงินจริงที่คาดหวังจาก DB (ตรวจสอบสถานะ 'pending')
            const [history] = await db.promise().query(
                'SELECT amount FROM topup_history WHERE id = ? AND status = "pending"', 
                [historyId]
            );
            
            if (history.length === 0) {
                 message = 'รายการชำระเงินไม่ถูกต้อง หรือสถานะไม่เป็น Pending';
                 throw new Error(message);
            }
            
            const requiredAmount = history[0].amount; 
            const numericRequiredAmount = parseFloat(requiredAmount); // 👈 แปลงเป็น Number ทันที

            // 2. ทำ OCR
            const result = await Tesseract.recognize(slipPath, "tha+eng");
            ocr_text = result.data.text; 

            // 🆕 3a. ดึงเลขที่อ้างอิง (ตัวอย่าง: รหัสอ้างอิง Krungthai A0f208... ยาว 16 ตัวอักษร)
            const refMatch = ocr_text.match(/[A-Za-z0-9]{16}/); 
            if (refMatch) {
                referenceNo = refMatch[0];
            }

            // 🆕 3b. ตรวจสอบเลขที่อ้างอิงซ้ำใน DB (ป้องกัน Replay Attack)
            if (referenceNo) {
                const [duplicate] = await db.promise().query(
                    'SELECT id FROM topup_history WHERE reference_no = ? AND status = "success"', 
                    [referenceNo]
                );
                
                if (duplicate.length > 0) {
                    message = 'สลิปนี้เคยถูกใช้ในการเติมเงินสำเร็จไปแล้ว';
                    status = 'failed';
                    throw new Error(message); // ยกเลิกการประมวลผลต่อ
                }
            }
            // ⚠️ ถ้าไม่พบ referenceNo จะดำเนินขั้นตอนต่อไป แต่จะถูกบันทึกเป็น NULL ใน DB
            
            // 3c. ดึงยอดเงินที่โอนจริง
            const match = ocr_text.match(/([0-9,]+\.[0-9]{2})/);
            if (match) {
                paidAmount = parseFloat(match[1].replace(/,/g, '')); 
            }
            
            // 4. ตรวจสอบยอดเงิน: แก้ปัญหา Floating Point
            const requiredAmountStr = numericRequiredAmount.toFixed(2);
            const paidAmountStr = paidAmount.toFixed(2);
            
            if (paidAmountStr === requiredAmountStr) { 
                status = 'success';
                coins = Math.floor(numericRequiredAmount); 
                message = 'Top-up successful';
                
                // 5. ถ้าสำเร็จ: อัปเดตยอด Coin ของ User
                await db.promise().query(`
                    UPDATE users SET coin_balance = coin_balance + ? WHERE id = ?
                `,[coins, user_id]);

                console.log(`✅ User ${user_id}: Top-up ${requiredAmount} SUCCESS. History ID: ${historyId}`);
            } else {
                message = `ยอดเงินที่โอนไม่ตรง (${paidAmount.toFixed(2)}) กับยอดที่ต้องโอน (${numericRequiredAmount.toFixed(2)})`;
                console.log(`❌ User ${user_id}: Top-up FAILED. Reason: ${message}. History ID: ${historyId}`);
            }

        } catch (e) {
            console.error(`OCR Process Fatal Error for history ID ${historyId}:`, e);
            message = e.message || 'OCR Processing Error';
        }

        // 6. อัปเดตสถานะสุดท้ายใน DB (เพิ่ม reference_no)
        await db.promise().query(`
            UPDATE topup_history 
            SET status = ?, coins_added = ?, ocr_text = ?, paid_amount = ?, message = ?, reference_no = ?
            WHERE id = ?
        `,[status, coins, ocr_text, paidAmount, message, referenceNo, historyId]); // 👈 เพิ่ม referenceNo

        // 7. ลบไฟล์สลิปชั่วคราวทิ้ง
        if (fs.existsSync(slipPath)) fs.unlinkSync(slipPath);
    }
    
    // ----------------------------------------------------
    // 4) API: เตรียมการชำระเงิน (/prepare-payment)
    // ----------------------------------------------------
    router.post('/prepare-payment', async (req, res) => {
        const { amount, user_id } = req.body;
        const baseAmount = parseFloat(amount);
        
        if (isNaN(baseAmount) || baseAmount <= 0) {
            return res.status(400).json({ message: 'Invalid amount' });
        }
        
        // 1. สร้างยอดเงินที่ไม่ซ้ำกัน
        const uniqueCents = generateUniqueCents();
        const uniqueAmount = parseFloat(`${baseAmount}.${uniqueCents}`);
        
        // 2. สร้าง QR Payload 
        const payload = generatePayload(promptpayNumber, { amount: uniqueAmount });
        
        let qrBase64Data = "";
        try {
            const img = await qrcode.toDataURL(payload);
            qrBase64Data = img.split(',')[1];
        } catch (error) {
            console.error("QR Generation Error:", error);
            return res.status(500).json({ message: 'Failed to generate QR code.' });
        }
        
        // 3. บันทึกยอดเงินที่ไม่ซ้ำกันนี้ลงใน DB สถานะ 'reserved'
        const [result] = await db.promise().query(`
            INSERT INTO topup_history (user_id, amount, coins_added, status)
            VALUES (?, ?, 0, 'reserved')
        `,[user_id, uniqueAmount]);
        
        const historyId = result.insertId;

        res.json({
            qr: qrBase64Data,
            unique_amount: uniqueAmount, 
            history_id: historyId
        });
    });


    // ----------------------------------------------------
    // 5) API: Upload Slip (/upload-slip)
    // ----------------------------------------------------
    router.post('/upload-slip', upload.single('slip'), async (req, res) => {
        
        const historyId = parseInt(req.body.history_id); 
        const user_id = req.body.user_id;
        const slipPath = req.file.path; 
        const fileName = req.file.filename;

        // ตรวจสอบ historyId ก่อน
        if (isNaN(historyId)) {
             if (fs.existsSync(slipPath)) fs.unlinkSync(slipPath);
             return res.status(400).json({ message: "Invalid history ID." });
        }
        
        try {
            // 1. อัปเดตสถานะเป็น pending และบันทึก slip_image
            const [updateResult] = await db.promise().query( 
                `UPDATE topup_history 
                SET slip_image = ?, status = 'pending'
                WHERE id = ? AND user_id = ? AND status = 'reserved'`,
                [fileName, historyId, user_id]
            );

            // ⚠️ FIX: ถ้า affectedRows เป็น 0 แสดงว่าสถานะไม่เป็น reserved แล้ว (ส่งซ้ำ)
            if (updateResult.affectedRows === 0) {
                if (fs.existsSync(slipPath)) fs.unlinkSync(slipPath);
                // ค้นหาว่ารายการนี้เคยสำเร็จไปแล้วหรือยัง
                const [checkStatus] = await db.promise().query(
                    'SELECT status FROM topup_history WHERE id = ?', [historyId]
                );
                
                let errorMessage = "ไม่สามารถส่งสลิปได้: รายการหมดอายุ หรือมีการดำเนินการไปแล้ว";
                if (checkStatus.length > 0 && checkStatus[0].status === 'success') {
                    errorMessage = "รายการนี้ได้รับการเติมเงินสำเร็จไปแล้ว";
                }
                
                return res.status(400).json({ 
                    message: errorMessage
                });
            }
            
            // 2. ตอบกลับ Client ทันที (Status 202: Accepted)
            res.status(202).json({
                message: "ได้รับสลิปแล้ว กำลังตรวจสอบสถานะ",
                history_id: historyId,
                status: 'pending'
            });
            
            // 3. เริ่มกระบวนการตรวจสอบ OCR เบื้องหลัง
            processSlip(historyId, user_id, slipPath); 

        } catch (e) {
            if (fs.existsSync(slipPath)) fs.unlinkSync(slipPath);
            console.error("Upload/Initial DB Error:", e);
            res.status(500).json({ message: "Upload Error or Database failed to record pending status." });
        }
    });

    // ----------------------------------------------------
    // 6) API: Check Topup Status (/status/:historyId)
    // ----------------------------------------------------
    router.get('/status/:historyId', async (req, res) => {
        const historyId = req.params.historyId;
        try {
            const [results] = await db.promise().query(
                'SELECT status, coins_added, message FROM topup_history WHERE id = ?', 
                [historyId]
            );

            if (results.length === 0) {
                return res.status(404).json({ message: 'History not found' });
            }

            res.json(results[0]); 
        } catch (e) {
            res.status(500).json({ message: 'Server error' });
        }
    });

    // ----------------------------------------------------
    // 7) API: Get Topup History (/history/:userId)
    // ----------------------------------------------------
    router.get('/history/:userId', async (req, res) => {
        const userId = req.params.userId;
        try {
            const [results] = await db.promise().query(
                'SELECT id, amount, coins_added, status, created_at, message, paid_amount FROM topup_history WHERE user_id = ? ORDER BY created_at DESC', 
                [userId]
            );

            res.json(results); 
        } catch (e) {
            console.error("Error fetching topup history:", e);
            res.status(500).json({ message: 'Server error fetching history' });
        }
    });

    return router;
};