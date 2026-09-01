'use strict';

const { db, now } = require('./config/firebase');

async function seedFullFirebaseConsole() {
  console.log('🚀 Starting Full Firebase Console Firestore Seeding...');

  try {
    // 1. Settings Collection
    await db.collection('settings').doc('default').set({
      appName: 'Online Equb Management System',
      appVersion: '1.0.0',
      environment: 'production',
      projectId: 'online-equb-managment-sy-b5517',
      equbRules: {
        lowLevel: { price: 500, cycle: 'Daily/Weekly', maxMembers: 100 },
        mediumLevel: { price: 2000, cycle: 'Weekly', maxMembers: 100 },
        highLevel: { price: 10000, cycle: 'Monthly', maxMembers: 100 },
      },
      updatedAt: now(),
    }, { merge: true });
    console.log('✅ Collection [settings]: document synced');

    // 2. Meta & Super Admin
    await db.collection('meta').doc('super_admin_profile').set({
      username: 'superadmin',
      email: 'superadmin@equb.et',
      fullName: 'Super Admin',
      phone: '+251911000000',
      role: 'super_admin',
      updatedAt: now(),
    }, { merge: true });

    await db.collection('super_admin').doc('admin').set({
      uid: 'super_admin_uid',
      email: 'superadmin@equb.et',
      username: 'superadmin',
      displayName: 'Super Admin',
      role: 'super_admin',
      status: 'active',
      updatedAt: now(),
    }, { merge: true });
    console.log('✅ Collection [meta] & [super_admin]: documents synced');

    // 3. Admins Collection
    const admins = [
      {
        adminId: 'admin_super',
        id: 'admin_super',
        fullName: 'Super Admin',
        username: 'superadmin',
        email: 'super@equb.et',
        phone: '+251911000000',
        role: 'super_admin',
        level: 'all',
        equbLevel: 'all',
        status: 'active',
      },
      {
        adminId: 'admin_low_1',
        id: 'admin_low_1',
        fullName: 'Low Level Admin',
        username: 'lowadmin',
        email: 'admin@equb.et',
        phone: '+251911000001',
        role: 'admin',
        level: 'low',
        equbLevel: 'low',
        status: 'active',
      },
      {
        adminId: 'admin_med_1',
        id: 'admin_med_1',
        fullName: 'Medium Level Admin',
        username: 'medadmin',
        email: 'medadmin@equb.et',
        phone: '+251911000002',
        role: 'admin',
        level: 'medium',
        equbLevel: 'medium',
        status: 'active',
      },
      {
        adminId: 'admin_high_1',
        id: 'admin_high_1',
        fullName: 'High Level Admin',
        username: 'highadmin',
        email: 'highadmin@equb.et',
        phone: '+251911000003',
        role: 'admin',
        level: 'high',
        equbLevel: 'high',
        status: 'active',
      },
    ];

    for (const adm of admins) {
      await db.collection('admins').doc(adm.adminId).set({
        ...adm,
        updatedAt: now(),
        createdAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [admins]: ${admins.length} documents synced`);

    // 4. Equbs Collection
    const equbs = [
      {
        equbId: 'eq_low',
        id: 'eq_low',
        level: 'low',
        equbLevel: 'low',
        titleEn: 'Low Level Equb',
        titleAm: 'ዝቅተኛ ደረጃ እቁብ',
        contributionAmount: 500,
        priceRange: '500 - 5,000 ETB',
        netPrize: 495000,
        maxParticipants: 100,
        totalMembers: 4,
        cycle: 'Daily/Weekly',
        status: 'active',
      },
      {
        equbId: 'eq_medium',
        id: 'eq_medium',
        level: 'medium',
        equbLevel: 'medium',
        titleEn: 'Medium Level Equb',
        titleAm: 'መካከለኛ ደረጃ እቁብ',
        contributionAmount: 2000,
        priceRange: '6,000 - 10,000 ETB',
        netPrize: 990000,
        maxParticipants: 100,
        totalMembers: 3,
        cycle: 'Weekly',
        status: 'active',
      },
      {
        equbId: 'eq_high',
        id: 'eq_high',
        level: 'high',
        equbLevel: 'high',
        titleEn: 'High Level Equb',
        titleAm: 'ከፍተኛ ደረጃ እቁብ',
        contributionAmount: 10000,
        priceRange: '11,000 - 20,000 ETB',
        netPrize: 1980000,
        maxParticipants: 100,
        totalMembers: 3,
        cycle: 'Monthly',
        status: 'active',
      },
    ];

    for (const eq of equbs) {
      await db.collection('equbs').doc(eq.equbId).set({
        ...eq,
        createdAt: now(),
        updatedAt: now(),
      }, { merge: true });

      // Mirror in equb_levels for fallback query compatibility
      await db.collection('equb_levels').doc(eq.level).set({
        level: eq.level,
        price: eq.contributionAmount,
        netPrize: eq.netPrize,
        maxParticipants: eq.maxParticipants,
        status: eq.status,
        updatedAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [equbs] & [equb_levels]: ${equbs.length} documents synced`);

    // 5. Users Collection (Members across Low, Medium, High Tiers)
    const users = [
      // Low Level
      {
        userId: 'usr_low_01',
        id: 'usr_low_01',
        fullName: 'Abebe Bikila',
        email: 'abebe@gmail.com',
        phoneNumber: '+251911121212',
        phone: '+251911121212',
        uniqueId: 'EQ-LOW-001',
        equbLevel: 'low',
        level: 'low',
        balance: 500,
        hasPaid: true,
        hasWon: true,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_low_02',
        id: 'usr_low_02',
        fullName: 'Derartu Tulu',
        email: 'derartu@gmail.com',
        phoneNumber: '+251911223344',
        phone: '+251911223344',
        uniqueId: 'EQ-LOW-002',
        equbLevel: 'low',
        level: 'low',
        balance: 500,
        hasPaid: true,
        hasWon: false,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_low_03',
        id: 'usr_low_03',
        fullName: 'Haile Gebrselassie',
        email: 'haile@gmail.com',
        phoneNumber: '+251911334455',
        phone: '+251911334455',
        uniqueId: 'EQ-LOW-003',
        equbLevel: 'low',
        level: 'low',
        balance: 0,
        hasPaid: false,
        hasWon: false,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_low_04',
        id: 'usr_low_04',
        fullName: 'Tirunesh Dibaba',
        email: 'tirunesh@gmail.com',
        phoneNumber: '+251911445566',
        phone: '+251911445566',
        uniqueId: 'EQ-LOW-004',
        equbLevel: 'low',
        level: 'low',
        balance: 500,
        hasPaid: true,
        hasWon: false,
        role: 'member',
        status: 'active',
      },

      // Medium Level
      {
        userId: 'usr_med_01',
        id: 'usr_med_01',
        fullName: 'Kebede Michael',
        email: 'kebede@gmail.com',
        phoneNumber: '+251922343434',
        phone: '+251922343434',
        uniqueId: 'EQ-MED-001',
        equbLevel: 'medium',
        level: 'medium',
        balance: 2000,
        hasPaid: true,
        hasWon: false,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_med_02',
        id: 'usr_med_02',
        fullName: 'Aster Aweke',
        email: 'aster@gmail.com',
        phoneNumber: '+251922445566',
        phone: '+251922445566',
        uniqueId: 'EQ-MED-002',
        equbLevel: 'medium',
        level: 'medium',
        balance: 2000,
        hasPaid: true,
        hasWon: true,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_med_03',
        id: 'usr_med_03',
        fullName: 'Teddy Afro',
        email: 'teddy@gmail.com',
        phoneNumber: '+251922556677',
        phone: '+251922556677',
        uniqueId: 'EQ-MED-003',
        equbLevel: 'medium',
        level: 'medium',
        balance: 0,
        hasPaid: false,
        hasWon: false,
        role: 'member',
        status: 'active',
      },

      // High Level
      {
        userId: 'usr_high_01',
        id: 'usr_high_01',
        fullName: 'Tilahun Gessesse',
        email: 'tilahun@gmail.com',
        phoneNumber: '+251933565656',
        phone: '+251933565656',
        uniqueId: 'EQ-HIGH-001',
        equbLevel: 'high',
        level: 'high',
        balance: 10000,
        hasPaid: true,
        hasWon: true,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_high_02',
        id: 'usr_high_02',
        fullName: 'Mahmoud Ahmed',
        email: 'mahmoud@gmail.com',
        phoneNumber: '+251933667788',
        phone: '+251933667788',
        uniqueId: 'EQ-HIGH-002',
        equbLevel: 'high',
        level: 'high',
        balance: 10000,
        hasPaid: true,
        hasWon: false,
        role: 'member',
        status: 'active',
      },
      {
        userId: 'usr_high_03',
        id: 'usr_high_03',
        fullName: 'Bizunesh Bekele',
        email: 'bizunesh@gmail.com',
        phoneNumber: '+251933778899',
        phone: '+251933778899',
        uniqueId: 'EQ-HIGH-003',
        equbLevel: 'high',
        level: 'high',
        balance: 0,
        hasPaid: false,
        hasWon: false,
        role: 'member',
        status: 'active',
      },
    ];

    for (const u of users) {
      await db.collection('users').doc(u.userId).set({
        ...u,
        createdAt: now(),
        updatedAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [users]: ${users.length} member documents synced`);

    // 6. Payments Collection
    const payments = [
      {
        paymentId: 'pay_low_1',
        id: 'pay_low_1',
        userId: 'usr_low_01',
        userName: 'Abebe Bikila',
        userEmail: 'abebe@gmail.com',
        userPhone: '+251911121212',
        equbLevel: 'low',
        level: 'low',
        amount: 500,
        paymentMethod: 'Telebirr',
        status: 'approved',
        verifiedBy: 'admin_low_1',
        receiptUrl: 'https://telebirr.com/receipt/001',
      },
      {
        paymentId: 'pay_low_2',
        id: 'pay_low_2',
        userId: 'usr_low_02',
        userName: 'Derartu Tulu',
        userEmail: 'derartu@gmail.com',
        userPhone: '+251911223344',
        equbLevel: 'low',
        level: 'low',
        amount: 500,
        paymentMethod: 'Telebirr',
        status: 'approved',
        verifiedBy: 'admin_low_1',
        receiptUrl: 'https://telebirr.com/receipt/002',
      },
      {
        paymentId: 'pay_low_3',
        id: 'pay_low_3',
        userId: 'usr_low_03',
        userName: 'Haile Gebrselassie',
        userEmail: 'haile@gmail.com',
        userPhone: '+251911334455',
        equbLevel: 'low',
        level: 'low',
        amount: 500,
        paymentMethod: 'CBE',
        status: 'pending',
        verifiedBy: null,
        receiptUrl: 'https://cbe.com.et/receipt/003',
      },
      {
        paymentId: 'pay_med_1',
        id: 'pay_med_1',
        userId: 'usr_med_01',
        userName: 'Kebede Michael',
        userEmail: 'kebede@gmail.com',
        userPhone: '+251922343434',
        equbLevel: 'medium',
        level: 'medium',
        amount: 2000,
        paymentMethod: 'Telebirr',
        status: 'approved',
        verifiedBy: 'admin_med_1',
        receiptUrl: 'https://telebirr.com/receipt/101',
      },
      {
        paymentId: 'pay_med_2',
        id: 'pay_med_2',
        userId: 'usr_med_02',
        userName: 'Aster Aweke',
        userEmail: 'aster@gmail.com',
        userPhone: '+251922445566',
        equbLevel: 'medium',
        level: 'medium',
        amount: 2000,
        paymentMethod: 'BOA',
        status: 'approved',
        verifiedBy: 'admin_med_1',
        receiptUrl: 'https://boa.com.et/receipt/102',
      },
      {
        paymentId: 'pay_med_3',
        id: 'pay_med_3',
        userId: 'usr_med_03',
        userName: 'Teddy Afro',
        userEmail: 'teddy@gmail.com',
        userPhone: '+251922556677',
        equbLevel: 'medium',
        level: 'medium',
        amount: 2000,
        paymentMethod: 'Telebirr',
        status: 'rejected',
        verifiedBy: 'admin_med_1',
        adminMessage: 'Receipt reference number invalid',
        receiptUrl: 'https://telebirr.com/receipt/103',
      },
      {
        paymentId: 'pay_high_1',
        id: 'pay_high_1',
        userId: 'usr_high_01',
        userName: 'Tilahun Gessesse',
        userEmail: 'tilahun@gmail.com',
        userPhone: '+251933565656',
        equbLevel: 'high',
        level: 'high',
        amount: 10000,
        paymentMethod: 'CBE',
        status: 'approved',
        verifiedBy: 'admin_high_1',
        receiptUrl: 'https://cbe.com.et/receipt/201',
      },
      {
        paymentId: 'pay_high_2',
        id: 'pay_high_2',
        userId: 'usr_high_02',
        userName: 'Mahmoud Ahmed',
        userEmail: 'mahmoud@gmail.com',
        userPhone: '+251933667788',
        equbLevel: 'high',
        level: 'high',
        amount: 10000,
        paymentMethod: 'CBE',
        status: 'approved',
        verifiedBy: 'admin_high_1',
        receiptUrl: 'https://cbe.com.et/receipt/202',
      },
    ];

    for (const p of payments) {
      await db.collection('payments').doc(p.paymentId).set({
        ...p,
        createdAt: now(),
        updatedAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [payments]: ${payments.length} payment documents synced`);

    // 7. Draws Collection (Draw History)
    const draws = [
      {
        drawId: 'draw_low_1',
        id: 'draw_low_1',
        drawNumber: 1,
        round: 1,
        equbLevel: 'low',
        level: 'low',
        winnerId: 'usr_low_01',
        winnerName: 'Abebe Bikila',
        winnerEmail: 'abebe@gmail.com',
        winnerPhone: '+251911121212',
        winnerUniqueId: 'EQ-LOW-001',
        netPrize: 495000,
        drawDate: now(),
        status: 'completed',
      },
      {
        drawId: 'draw_med_1',
        id: 'draw_med_1',
        drawNumber: 1,
        round: 1,
        equbLevel: 'medium',
        level: 'medium',
        winnerId: 'usr_med_02',
        winnerName: 'Aster Aweke',
        winnerEmail: 'aster@gmail.com',
        winnerPhone: '+251922445566',
        winnerUniqueId: 'EQ-MED-002',
        netPrize: 990000,
        drawDate: now(),
        status: 'completed',
      },
      {
        drawId: 'draw_high_1',
        id: 'draw_high_1',
        drawNumber: 1,
        round: 1,
        equbLevel: 'high',
        level: 'high',
        winnerId: 'usr_high_01',
        winnerName: 'Tilahun Gessesse',
        winnerEmail: 'tilahun@gmail.com',
        winnerPhone: '+251933565656',
        winnerUniqueId: 'EQ-HIGH-001',
        netPrize: 1980000,
        drawDate: now(),
        status: 'completed',
      },
    ];

    for (const d of draws) {
      await db.collection('draws').doc(d.drawId).set({
        ...d,
        createdAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [draws]: ${draws.length} draw history documents synced`);

    // 8. Notifications Collection
    const notifications = [
      {
        notificationId: 'notif_low_1',
        id: 'notif_low_1',
        userId: 'usr_low_01',
        userEmail: 'abebe@gmail.com',
        userPhone: '+251911121212',
        title: 'Payment Approved ✅',
        message: 'Your contribution of 500 ETB for Low Level Equb has been approved.',
        status: 'approved',
        equbLevel: 'low',
        level: 'low',
        amount: 500,
        read: true,
      },
      {
        notificationId: 'notif_low_2',
        id: 'notif_low_2',
        userId: 'usr_low_01',
        userEmail: 'abebe@gmail.com',
        userPhone: '+251911121212',
        title: 'Equb Draw Winner Announced! 🎉',
        message: 'Congratulations Abebe Bikila! You won Round 1 of Low Level Equb (495,000 ETB).',
        status: 'approved',
        equbLevel: 'low',
        level: 'low',
        amount: 495000,
        read: false,
      },
      {
        notificationId: 'notif_med_1',
        id: 'notif_med_1',
        userId: 'usr_med_02',
        userEmail: 'aster@gmail.com',
        userPhone: '+251922445566',
        title: 'Payment Approved ✅',
        message: 'Your contribution of 2,000 ETB for Medium Level Equb has been approved.',
        status: 'approved',
        equbLevel: 'medium',
        level: 'medium',
        amount: 2000,
        read: false,
      },
      {
        notificationId: 'notif_med_2',
        id: 'notif_med_2',
        userId: 'usr_med_03',
        userEmail: 'teddy@gmail.com',
        userPhone: '+251922556677',
        title: 'Payment Rejected ❌',
        message: 'Your contribution of 2,000 ETB was rejected. Reason: Receipt reference number invalid.',
        status: 'rejected',
        equbLevel: 'medium',
        level: 'medium',
        amount: 2000,
        read: false,
      },
      {
        notificationId: 'notif_high_1',
        id: 'notif_high_1',
        userId: 'usr_high_01',
        userEmail: 'tilahun@gmail.com',
        userPhone: '+251933565656',
        title: 'Payment Approved ✅',
        message: 'Your contribution of 10,000 ETB for High Level Equb has been approved.',
        status: 'approved',
        equbLevel: 'high',
        level: 'high',
        amount: 10000,
        read: true,
      },
    ];

    for (const n of notifications) {
      await db.collection('notifications').doc(n.notificationId).set({
        ...n,
        createdAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [notifications]: ${notifications.length} notification documents synced`);

    // 9. Payment Methods Collection
    const paymentMethods = [
      { methodId: 'pm_telebirr', name: 'Telebirr', accountNumber: '0911000000', status: 'active' },
      { methodId: 'pm_cbe', name: 'Commercial Bank of Ethiopia', accountNumber: '1000123456789', status: 'active' },
      { methodId: 'pm_boa', name: 'Bank of Abyssinia', accountNumber: '88776655', status: 'active' },
    ];

    for (const pm of paymentMethods) {
      await db.collection('payment_methods').doc(pm.methodId).set({
        ...pm,
        createdAt: now(),
      }, { merge: true });
    }
    console.log(`✅ Collection [payment_methods]: ${paymentMethods.length} method documents synced`);

    // 10. Audit Logs
    await db.collection('audit_logs').doc('log_001').set({
      logId: 'log_001',
      action: 'SYSTEM_FULL_SEEDED',
      performedBy: 'service_account',
      target: 'all_collections',
      timestamp: now(),
    }, { merge: true });
    console.log('✅ Collection [audit_logs]: document synced');

    console.log('🎉 FULL FIREBASE DATA CONSOLE POPULATED AND STORED SUCCESSFULLY!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error seeding Firebase Console:', err);
    process.exit(1);
  }
}

seedFullFirebaseConsole();
