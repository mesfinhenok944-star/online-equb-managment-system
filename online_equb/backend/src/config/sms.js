'use strict';

// ─────────────────────────────────────────────────────────────────────────────
// SMS Service — Africa's Talking (supports Ethiopian +251 numbers)
//
// Setup (free trial at https://africastalking.com):
//   1. Sign up → get USERNAME and API_KEY
//   2. Add to backend/.env:
//      AT_USERNAME=sandbox          (or your real username)
//      AT_API_KEY=your-api-key-here
//      AT_SENDER_ID=EQUB            (optional, max 11 chars)
//
// Free sandbox: use username=sandbox, send to your registered sandbox numbers
// Production:   use real username + funded account
// ─────────────────────────────────────────────────────────────────────────────

const crypto = require('crypto');

// In-memory OTP store  { phone: { otp, expiresAt } }
const otpStore = new Map();
const OTP_TTL_MS = 10 * 60 * 1000; // 10 minutes

let atClient = null;
let atSms    = null;

function isAtConfigured() {
  return !!(process.env.AT_USERNAME && process.env.AT_API_KEY);
}

function getAtSms() {
  if (atSms) return atSms;
  if (!isAtConfigured()) return null;
  try {
    const AfricasTalking = require('africastalking');
    atClient = AfricasTalking({
      username: process.env.AT_USERNAME,
      apiKey:   process.env.AT_API_KEY,
    });
    atSms = atClient.SMS;
    return atSms;
  } catch (err) {
    console.error('[SMS] Init error:', err.message);
    return null;
  }
}

// ── Generate OTP ──────────────────────────────────────────────────────────────
function generateOtp() {
  // 6-digit cryptographically secure OTP
  const bytes  = crypto.randomBytes(3);
  const num    = parseInt(bytes.toString('hex'), 16);
  const otp    = String(num % 1000000).padStart(6, '0');
  return otp;
}

// ── Store OTP ─────────────────────────────────────────────────────────────────
function storeOtp(identifier, otp) {
  otpStore.set(identifier.toLowerCase().trim(), {
    otp,
    expiresAt: Date.now() + OTP_TTL_MS,
  });
}

// ── Verify OTP ────────────────────────────────────────────────────────────────
function verifyOtp(identifier, inputOtp) {
  const key    = identifier.toLowerCase().trim();
  const record = otpStore.get(key);
  if (!record) return { valid: false, reason: 'No OTP found. Please request a new one.' };
  if (Date.now() > record.expiresAt) {
    otpStore.delete(key);
    return { valid: false, reason: 'OTP expired. Please request a new one.' };
  }
  if (record.otp !== inputOtp.trim()) {
    return { valid: false, reason: 'Incorrect OTP. Please try again.' };
  }
  otpStore.delete(key); // one-time use
  return { valid: true };
}

// ── Send SMS OTP ──────────────────────────────────────────────────────────────
async function sendOtpSms(phone, otp) {
  // Normalise Ethiopian number (+251 or 09xxx)
  let normalized = phone.trim().replace(/\s+/g, '');
  if (normalized.startsWith('09') || normalized.startsWith('07')) {
    normalized = '+251' + normalized.substring(1);
  } else if (normalized.startsWith('251') && !normalized.startsWith('+')) {
    normalized = '+' + normalized;
  }

  const message = `Your Digital Equb verification code is: ${otp}\nValid for 10 minutes.\nDo not share this code.\n\nDigital Equb`;

  const sms = getAtSms();
  if (!sms) {
    console.log(`[SMS] Not configured — OTP for ${normalized}: ${otp}`);
    return { success: true, simulated: true, otp }; // dev mode — OTP visible in logs
  }

  try {
    const result = await sms.send({
      to:      [normalized],
      message,
      from:    process.env.AT_SENDER_ID || 'EQUB',
    });
    console.log('[SMS] Sent to', normalized, ':', JSON.stringify(result.SMSMessageData?.Recipients?.[0]?.status));
    return { success: true, phone: normalized };
  } catch (err) {
    console.error('[SMS] Error:', err.message);
    return { success: false, error: err.message };
  }
}

// ── Send payment notification SMS ─────────────────────────────────────────────
async function sendPaymentSms({ phone, fullName, status, amount, level, rejectionReason = '' }) {
  if (!phone || phone.trim().length < 9) return { success: false, reason: 'No phone' };

  let normalized = phone.trim().replace(/\s+/g, '');
  if (normalized.startsWith('09') || normalized.startsWith('07')) {
    normalized = '+251' + normalized.substring(1);
  } else if (normalized.startsWith('251') && !normalized.startsWith('+')) {
    normalized = '+' + normalized;
  }

  const lvlAm = level === 'high' ? 'ከፍተኛ ደረጃ' : level === 'medium' ? 'መካከለኛ ደረጃ' : 'ዝቅተኛ ደረጃ';

  const message = status === 'verified'
    ? `✅ Dear ${fullName}, your ${lvlAm} equb payment of ETB ${amount} has been APPROVED. Thank you! - Digital Equb`
    : `❌ Dear ${fullName}, your ${lvlAm} equb payment was REJECTED. Reason: ${rejectionReason || 'See admin'}. Please resubmit. - Digital Equb`;

  const sms = getAtSms();
  if (!sms) {
    console.log(`[SMS] Not configured — would send to ${normalized}: ${message.substring(0,60)}...`);
    return { success: true, simulated: true };
  }

  try {
    await sms.send({ to: [normalized], message, from: process.env.AT_SENDER_ID || 'EQUB' });
    console.log('[SMS] Payment notification sent to:', normalized);
    return { success: true };
  } catch (err) {
    console.error('[SMS] Payment SMS error:', err.message);
    return { success: false, error: err.message };
  }
}

module.exports = { generateOtp, storeOtp, verifyOtp, sendOtpSms, sendPaymentSms, isAtConfigured };
