'use strict';

const { db, now } = require('./config/firebase');

async function migrateDatabase() {
  console.log('🔄 Starting Full Database Migration & Seeding for 14 Collections...');

  try {
    // 1. Settings Collection
    const settingsRef = db.collection('settings').doc('default');
    await settingsRef.set({
      general: {
        appName: 'Online Equb',
        appVersion: '1.0.0',
        environment: 'production',
        maintenanceMode: false,
      },
      equbRules: {
        maxAdminsPerLevel: 3,
        lowPriceRange: '500 - 5,000',
        mediumPriceRange: '6,000 - 10,000',
        highPriceRange: '11,000 - 20,000',
      },
      createdAt: now(),
      updatedAt: now(),
    }, { merge: true });
    console.log('✅ 1. Settings collection created/synced');

    // 2. Super Admin Collection
    const superAdminRef = db.collection('super_admin').doc('admin');
    await superAdminRef.set({
      uid: 'super_admin_uid',
      email: 'abe@gmail.com',
      username: 'abebe1212',
      displayName: 'Super Admin',
      isActive: true,
      role: 'super_admin',
      createdAt: now(),
      updatedAt: now(),
    }, { merge: true });
    console.log('✅ 2. Super_admin collection created/synced');

    // Also mirror super_admin profile in meta collection for legacy access
    await db.collection('meta').doc('super_admin_profile').set({
      username: 'abebe1212',
      email: 'abe@gmail.com',
      fullName: 'Super Admin',
      role: 'super_admin',
      updatedAt: now(),
    }, { merge: true });

    // 3. Admins Collection
    const defaultAdmins = [
      { adminId: 'admin_low_1', fullName: 'Low Level Admin', username: 'lowadmin', email: 'lowadmin@equb.et', level: 'low', assignedLevel: 'low', role: 'admin', status: 'active', phone: '+251911000001' },
      { adminId: 'admin_med_1', fullName: 'Medium Level Admin', username: 'medadmin', email: 'medadmin@equb.et', level: 'medium', assignedLevel: 'medium', role: 'admin', status: 'active', phone: '+251911000002' },
      { adminId: 'admin_high_1', fullName: 'High Level Admin', username: 'highadmin', email: 'highadmin@equb.et', level: 'high', assignedLevel: 'high', role: 'admin', status: 'active', phone: '+251911000003' },
    ];

    for (const adm of defaultAdmins) {
      await db.collection('admins').doc(adm.adminId).set({
        ...adm,
        updatedAt: now(),
      }, { merge: true });
    }
    console.log('✅ 3. Admins collection created/synced (3 level admins)');

    // 4. Equbs Collection
    const equbsList = [
      { equbId: 'eq_low', level: 'low', titleEn: 'Low Level Equb', titleAm: 'ዝቅተኛ ደረጃ እቁብ', priceRange: '500 - 5,000 ETB', netPrize: 495000, maxParticipants: 100, status: 'active' },
      { equbId: 'eq_medium', level: 'medium', titleEn: 'Medium Level Equb', titleAm: 'መካከለኛ ደረጃ እቁብ', priceRange: '6,000 - 10,000 ETB', netPrize: 990000, maxParticipants: 100, status: 'active' },
      { equbId: 'eq_high', level: 'high', titleEn: 'High Level Equb', titleAm: 'ከፍተኛ ደረጃ እቁብ', priceRange: '11,000 - 20,000 ETB', netPrize: 1980000, maxParticipants: 100, status: 'active' },
    ];

    for (const eq of equbsList) {
      await db.collection('equbs').doc(eq.equbId).set({
        ...eq,
        createdAt: now(),
        updatedAt: now(),
      }, { merge: true });
    }
    console.log('✅ 4. Equbs collection created/synced');

    // Also sync equb_levels for legacy compatibility
    for (const eq of equbsList) {
      await db.collection('equb_levels').doc(eq.level).set({
        level: eq.level,
        price: eq.level === 'low' ? 5000 : (eq.level === 'medium' ? 10000 : 20000),
        maxParticipants: eq.maxParticipants,
        status: eq.status,
        updatedAt: now(),
      }, { merge: true });
    }

    // 5. Users Collection
    const sampleUsers = [
      { userId: 'usr_low_01', fullName: 'Abebe Bikila', phoneNumber: '+251911121212', uniqueId: 'EQ-LOW-001', equbLevel: 'low', hasWon: false, status: 'active', balance: 5000 },
      { userId: 'usr_med_01', fullName: 'Kebede Michael', phoneNumber: '+251922343434', uniqueId: 'EQ-MED-001', equbLevel: 'medium', hasWon: false, status: 'active', balance: 10000 },
      { userId: 'usr_high_01', fullName: 'Tilahun Gessesse', phoneNumber: '+251933565656', uniqueId: 'EQ-HIGH-001', equbLevel: 'high', hasWon: false, status: 'active', balance: 20000 },
    ];

    for (const u of sampleUsers) {
      await db.collection('users').doc(u.userId).set({
        ...u,
        createdAt: now(),
        updatedAt: now(),
      }, { merge: true });
    }
    console.log('✅ 5. Users collection created/synced');

    // 6. Payments Collection
    const samplePayment = {
      paymentId: 'pay_001',
      userId: 'usr_low_01',
      equbLevel: 'low',
      amount: 5000,
      paymentMethod: 'Telebirr',
      status: 'completed',
      createdAt: now(),
    };
    await db.collection('payments').doc(samplePayment.paymentId).set(samplePayment, { merge: true });
    console.log('✅ 6. Payments collection created/synced');

    // 7. Draws Collection
    const sampleDraw = {
      drawId: 'draw_001',
      drawNumber: 1,
      equbLevel: 'low',
      winnerId: 'usr_low_01',
      winnerName: 'Abebe Bikila',
      winnerUniqueId: 'EQ-LOW-001',
      netPrize: 495000,
      drawDate: now(),
      createdAt: now(),
    };
    await db.collection('draws').doc(sampleDraw.drawId).set(sampleDraw, { merge: true });
    console.log('✅ 7. Draws collection created/synced');

    // 8. Notifications Collection
    const sampleNotification = {
      notificationId: 'notif_001',
      userId: 'usr_low_01',
      title: 'Equb Draw Winner Announced!',
      message: 'Congratulations Abebe Bikila! You won Round 1 of Low Level Equb.',
      read: false,
      createdAt: now(),
    };
    await db.collection('notifications').doc(sampleNotification.notificationId).set(sampleNotification, { merge: true });
    console.log('✅ 8. Notifications collection created/synced');

    // 9. Transactions Collection
    const sampleTransaction = {
      transactionId: 'txn_001',
      userId: 'usr_low_01',
      type: 'contribution',
      amount: 5000,
      equbLevel: 'low',
      status: 'success',
      createdAt: now(),
    };
    await db.collection('transactions').doc(sampleTransaction.transactionId).set(sampleTransaction, { merge: true });
    console.log('✅ 9. Transactions collection created/synced');

    // 10. Disputes Collection
    const sampleDispute = {
      disputeId: 'disp_001',
      userId: 'usr_low_01',
      subject: 'Payment Verification Query',
      description: 'My Telebirr contribution was pending approval.',
      status: 'resolved',
      resolvedBy: 'admin_low_1',
      createdAt: now(),
    };
    await db.collection('disputes').doc(sampleDispute.disputeId).set(sampleDispute, { merge: true });
    console.log('✅ 10. Disputes collection created/synced');

    // 11. Payment Methods Collection
    const samplePaymentMethod = {
      methodId: 'pm_telebirr',
      name: 'Telebirr',
      accountNumber: '127.0.0.1:8080/telebirr',
      status: 'active',
      createdAt: now(),
    };
    await db.collection('payment_methods').doc(samplePaymentMethod.methodId).set(samplePaymentMethod, { merge: true });
    console.log('✅ 11. Payment_methods collection created/synced');

    // 12. Audit Logs Collection
    const sampleAuditLog = {
      logId: 'log_001',
      action: 'ADMIN_ASSIGNED',
      performedBy: 'super_admin_uid',
      target: 'admin_low_1',
      timestamp: now(),
    };
    await db.collection('audit_logs').doc(sampleAuditLog.logId).set(sampleAuditLog, { merge: true });
    console.log('✅ 12. Audit_logs collection created/synced');

    // 13. Reports Collection
    const sampleReport = {
      reportId: 'rep_001',
      title: 'Weekly Level Performance Report',
      level: 'low',
      totalCollected: 500000,
      totalWinners: 1,
      createdAt: now(),
    };
    await db.collection('reports').doc(sampleReport.reportId).set(sampleReport, { merge: true });
    console.log('✅ 13. Reports collection created/synced');

    // 14. System Logs Collection
    const sampleSystemLog = {
      sysLogId: 'syslog_001',
      level: 'INFO',
      message: 'Equb backend initialized and live connected.',
      createdAt: now(),
    };
    await db.collection('system_logs').doc(sampleSystemLog.sysLogId).set(sampleSystemLog, { merge: true });
    console.log('✅ 14. System_logs collection created/synced');

    console.log('🎉 ALL 14 DATABASE COLLECTIONS SUCCESSFULLY CREATED & SYNCED TO LIVE FIREBASE!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

migrateDatabase();
