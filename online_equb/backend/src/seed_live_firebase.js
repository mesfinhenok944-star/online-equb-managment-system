'use strict';

const { db, now } = require('./config/firebase');

async function seedLiveFirebase() {
  console.log('Seeding Live Firebase Firestore collections...');

  // 1. equb_levels
  const levels = [
    { level: 'low', price: 5000, maxParticipants: 100, status: 'active', nameEn: 'Low Level Equb', nameAm: 'ዝቅተኛ ደረጃ እቁብ' },
    { level: 'medium', price: 10000, maxParticipants: 50, status: 'active', nameEn: 'Medium Level Equb', nameAm: 'መካከለኛ ደረጃ እቁብ' },
    { level: 'high', price: 20000, maxParticipants: 20, status: 'active', nameEn: 'High Level Equb', nameAm: 'ከፍተኛ ደረጃ እቁብ' },
  ];

  for (const lvl of levels) {
    await db.collection('equb_levels').doc(lvl.level).set({
      ...lvl,
      updatedAt: now(),
    }, { merge: true });
    console.log(`✓ Collection equb_levels: level "${lvl.level}" synced.`);
  }

  // 2. super_admins
  await db.collection('meta').doc('super_admin_profile').set({
    username: 'superadmin',
    email: 'superadmin@equb.et',
    fullName: 'Super Admin',
    role: 'super_admin',
    updatedAt: now(),
  }, { merge: true });
  console.log('✓ Collection meta: doc "super_admin_profile" synced.');

  // 3. admins (Low, Medium, High)
  const defaultAdmins = [
    { adminId: 'admin_low_1', fullName: 'Low Level Admin', username: 'lowadmin', email: 'lowadmin@equb.et', level: 'low', role: 'admin', status: 'active', phone: '+251911000001' },
    { adminId: 'admin_med_1', fullName: 'Medium Level Admin', username: 'medadmin', email: 'medadmin@equb.et', level: 'medium', role: 'admin', status: 'active', phone: '+251911000002' },
    { adminId: 'admin_high_1', fullName: 'High Level Admin', username: 'highadmin', email: 'highadmin@equb.et', level: 'high', role: 'admin', status: 'active', phone: '+251911000003' },
  ];

  for (const adm of defaultAdmins) {
    await db.collection('admins').doc(adm.adminId).set({
      ...adm,
      updatedAt: now(),
    }, { merge: true });
    console.log(`✓ Collection admins: doc "${adm.adminId}" synced.`);
  }

  // 4. users (equb members)
  const defaultUsers = [
    { userId: 'usr_low_01', fullName: 'Abebe Bikila', phoneNumber: '+251911121212', uniqueId: 'EQ-LOW-001', equbLevel: 'low', hasWon: false, status: 'active' },
    { userId: 'usr_med_01', fullName: 'Kebede Michael', phoneNumber: '+251922343434', uniqueId: 'EQ-MED-001', equbLevel: 'medium', hasWon: false, status: 'active' },
    { userId: 'usr_high_01', fullName: 'Tilahun Gessesse', phoneNumber: '+251933565656', uniqueId: 'EQ-HIGH-001', equbLevel: 'high', hasWon: false, status: 'active' },
  ];

  for (const u of defaultUsers) {
    await db.collection('users').doc(u.userId).set({
      ...u,
      createdAt: now(),
      updatedAt: now(),
    }, { merge: true });
    console.log(`✓ Collection users: doc "${u.userId}" synced.`);
  }

  // 5. draws (draw history)
  await db.collection('draws').doc('draw_sample_01').set({
    drawId: 'draw_sample_01',
    drawNumber: 1,
    equbLevel: 'low',
    winnerName: 'Abebe Bikila',
    winnerUniqueId: 'EQ-LOW-001',
    netPrize: 495000,
    createdAt: now(),
  }, { merge: true });
  console.log('✓ Collection draws: doc "draw_sample_01" synced.');

  console.log('🎉 Live Firebase Firestore seeding completed successfully!');
  process.exit(0);
}

seedLiveFirebase().catch((err) => {
  console.error('Seeding error:', err);
  process.exit(1);
});
