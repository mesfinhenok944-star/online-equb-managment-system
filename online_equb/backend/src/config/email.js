'use strict';

const nodemailer = require('nodemailer');

// ─────────────────────────────────────────────────────────────────────────────
// Email Service
//
// Uses Gmail SMTP (or any SMTP) to send payment notifications to equb members.
// Set environment variables:
//   EMAIL_HOST     (default: smtp.gmail.com)
//   EMAIL_PORT     (default: 587)
//   EMAIL_USER     — your Gmail address (e.g. equbapp@gmail.com)
//   EMAIL_PASS     — Gmail app password (not your account password)
//   EMAIL_FROM     — display name + address
//
// To create a Gmail App Password:
//   Google Account → Security → 2-Step Verification → App passwords
// ─────────────────────────────────────────────────────────────────────────────

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  transporter = nodemailer.createTransport({
    host:   process.env.EMAIL_HOST || 'smtp.gmail.com',
    port:   parseInt(process.env.EMAIL_PORT || '587', 10),
    secure: process.env.EMAIL_SECURE === 'true', // true for 465
    auth: {
      user: process.env.EMAIL_USER || '',
      pass: process.env.EMAIL_PASS || '',
    },
  });
  return transporter;
}

function isEmailConfigured() {
  return !!(process.env.EMAIL_USER && process.env.EMAIL_PASS);
}

// ── Payment Approval Email ────────────────────────────────────────────────────
async function sendPaymentApprovedEmail({ to, fullName, amount, level, referenceNumber }) {
  if (!isEmailConfigured()) {
    console.log('[Email] Not configured — skipping approval email to:', to);
    return false;
  }
  const lvlAm = level === 'high' ? 'ከፍተኛ ደረጃ' : level === 'medium' ? 'መካከለኛ ደረጃ' : 'ዝቅተኛ ደረጃ';
  const mailOptions = {
    from: process.env.EMAIL_FROM || `"Digital Equb" <${process.env.EMAIL_USER}>`,
    to,
    subject: `✅ Payment Approved — ${level.toUpperCase()} Level Equb`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;border:1px solid #ddd;border-radius:12px;overflow:hidden;">
        <div style="background:linear-gradient(135deg,#009A44,#007A36);padding:28px 24px;text-align:center;">
          <h1 style="color:#FFD700;margin:0;font-size:24px;">✅ ክፍያዎ ፀድቋል!</h1>
          <p style="color:#fff;margin:8px 0 0;">Your Payment Has Been Approved</p>
        </div>
        <div style="padding:24px;">
          <p style="font-size:16px;color:#333;">Dear <strong>${fullName}</strong>,</p>
          <p style="color:#555;">Your equb payment has been <strong style="color:#009A44;">verified and approved</strong> by the admin.</p>
          <table style="width:100%;border-collapse:collapse;margin:20px 0;border-radius:8px;overflow:hidden;">
            <tr style="background:#f0faf4;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Equb Level</td>
              <td style="padding:12px 16px;color:#009A44;font-weight:bold;">${level.toUpperCase()} — ${lvlAm}</td>
            </tr>
            <tr style="background:#fff;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Amount</td>
              <td style="padding:12px 16px;color:#333;font-weight:bold;">ETB ${amount}</td>
            </tr>
            <tr style="background:#f0faf4;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Reference #</td>
              <td style="padding:12px 16px;color:#333;">${referenceNumber || '—'}</td>
            </tr>
            <tr style="background:#fff;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Status</td>
              <td style="padding:12px 16px;"><span style="background:#009A44;color:#fff;padding:4px 12px;border-radius:12px;font-size:12px;">APPROVED ✅</span></td>
            </tr>
          </table>
          <p style="color:#555;">Your contribution has been recorded. Thank you for participating in the Digital Equb!</p>
          <p style="color:#888;font-size:13px;margin-top:20px;">— Digital Equb Management System</p>
        </div>
      </div>
    `,
  };
  try {
    await getTransporter().sendMail(mailOptions);
    console.log('[Email] Approval email sent to:', to);
    return true;
  } catch (err) {
    console.error('[Email] Failed to send approval email:', err.message);
    return false;
  }
}

// ── Payment Rejection Email ───────────────────────────────────────────────────
async function sendPaymentRejectedEmail({ to, fullName, amount, level, rejectionReason, referenceNumber }) {
  if (!isEmailConfigured()) {
    console.log('[Email] Not configured — skipping rejection email to:', to);
    return false;
  }
  const lvlAm = level === 'high' ? 'ከፍተኛ ደረጃ' : level === 'medium' ? 'መካከለኛ ደረጃ' : 'ዝቅተኛ ደረጃ';
  const mailOptions = {
    from: process.env.EMAIL_FROM || `"Digital Equb" <${process.env.EMAIL_USER}>`,
    to,
    subject: `❌ Payment Rejected — ${level.toUpperCase()} Level Equb`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;border:1px solid #ddd;border-radius:12px;overflow:hidden;">
        <div style="background:linear-gradient(135deg,#D7141A,#a00010);padding:28px 24px;text-align:center;">
          <h1 style="color:#fff;margin:0;font-size:24px;">❌ ክፍያዎ ተሰርዟል</h1>
          <p style="color:#ffcccc;margin:8px 0 0;">Your Payment Has Been Rejected</p>
        </div>
        <div style="padding:24px;">
          <p style="font-size:16px;color:#333;">Dear <strong>${fullName}</strong>,</p>
          <p style="color:#555;">Unfortunately, your equb payment has been <strong style="color:#D7141A;">rejected</strong> by the admin.</p>
          <table style="width:100%;border-collapse:collapse;margin:20px 0;border-radius:8px;overflow:hidden;">
            <tr style="background:#fff5f5;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Equb Level</td>
              <td style="padding:12px 16px;color:#D7141A;font-weight:bold;">${level.toUpperCase()} — ${lvlAm}</td>
            </tr>
            <tr style="background:#fff;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Amount</td>
              <td style="padding:12px 16px;color:#333;font-weight:bold;">ETB ${amount}</td>
            </tr>
            <tr style="background:#fff5f5;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Reference #</td>
              <td style="padding:12px 16px;color:#333;">${referenceNumber || '—'}</td>
            </tr>
            <tr style="background:#fff;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Reason</td>
              <td style="padding:12px 16px;color:#D7141A;font-weight:bold;">${rejectionReason || 'See admin for details'}</td>
            </tr>
            <tr style="background:#fff5f5;">
              <td style="padding:12px 16px;color:#555;font-weight:bold;">Status</td>
              <td style="padding:12px 16px;"><span style="background:#D7141A;color:#fff;padding:4px 12px;border-radius:12px;font-size:12px;">REJECTED ❌</span></td>
            </tr>
          </table>
          <div style="background:#fff8e1;border-left:4px solid #FFD700;padding:12px 16px;border-radius:4px;margin:16px 0;">
            <p style="margin:0;color:#555;font-size:14px;"><strong>ምን ማድረግ ይቻላል? / What to do next:</strong><br>
            Please resubmit your payment with a clear bank receipt screenshot. Make sure the reference number matches exactly.</p>
          </div>
          <p style="color:#888;font-size:13px;margin-top:20px;">— Digital Equb Management System</p>
        </div>
      </div>
    `,
  };
  try {
    await getTransporter().sendMail(mailOptions);
    console.log('[Email] Rejection email sent to:', to);
    return true;
  } catch (err) {
    console.error('[Email] Failed to send rejection email:', err.message);
    return false;
  }
}

module.exports = { sendPaymentApprovedEmail, sendPaymentRejectedEmail, isEmailConfigured };
