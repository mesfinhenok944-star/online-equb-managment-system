// backend/src/routes/equbs_draw.js

'use strict';

const { Router } = require('express');
const { db, now, nowIso } = require('../config/firebase');
const { verifyToken, requireAdmin } = require('../middleware/auth');

const router = Router();

// Require admin token for all routes
router.use(verifyToken, requireAdmin);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/equbs/draw
// Run the equb draw algorithm for the admin's level
// ─────────────────────────────────────────────────────────────────────────────
router.post('/draw', async (req, res) => {
  try {
    const adminLevel = req.user?.level || 'low';
    const adminId = req.user?.adminId || '';

    // Get all active users who haven't won yet for this level
    const usersSnapshot = await db.collection('users')
      .where('level', '==', adminLevel)
      .where('status', '==', 'active')
      .where('hasWon', '==', false)
      .get();

    if (usersSnapshot.empty) {
      return res.status(400).json({
        error: 'No eligible participants available for this draw'
      });
    }

    // Get participant list
    const participants = usersSnapshot.docs.map(doc => ({
      userId: doc.id,
      ...doc.data()
    }));

    // Run fair weighted selection algorithm
    const winner = selectFairWinner(participants);

    if (!winner) {
      return res.status(500).json({
        error: 'Failed to select winner'
      });
    }

    // Save draw result
    const drawData = {
      level: adminLevel,
      adminId,
      winnerId: winner.userId,
      winnerName: `${winner.firstName} ${winner.lastName}`,
      winnerNationalId: winner.nationalId,
      totalParticipants: participants.length,
      participants: participants.map(p => p.userId),
      createdAt: now()
    };

    const drawRef = await db.collection('draws').add(drawData);

    // Update user's hasWon status
    await db.collection('users').doc(winner.userId).update({
      hasWon: true,
      lastWinDate: now(),
      updatedAt: now()
    });

    // Create winner notification
    await db.collection('notifications').add({
      userId: winner.userId,
      type: 'winner',
      title: '🎉 Congratulations!',
      message: `You have been selected as the winner for the ${adminLevel} Level Equb!`,
      isRead: false,
      createdAt: now()
    });

    // Get recent draw history
    const historySnapshot = await db.collection('draws')
      .where('level', '==', adminLevel)
      .orderBy('createdAt', 'desc')
      .limit(10)
      .get();

    const history = historySnapshot.docs.map(doc => ({
      drawId: doc.id,
      ...doc.data()
    }));

    return res.status(200).json({
      message: 'Draw completed successfully',
      data: {
        drawId: drawRef.id,
        winner: {
          userId: winner.userId,
          name: `${winner.firstName} ${winner.lastName}`,
          nationalId: winner.nationalId,
          email: winner.email,
          phoneNumber: winner.phoneNumber
        },
        totalParticipants: participants.length,
        drawTime: nowIso(),
        history
      }
    });
  } catch (error) {
    console.error('[equbs/draw]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/draws?level=low|medium|high&limit=10
// Get draw history for a level
// ─────────────────────────────────────────────────────────────────────────────
router.get('/draws', async (req, res) => {
  try {
    const adminLevel = req.user?.level || 'low';
    const { limit = 10 } = req.query;

    const snapshot = await db.collection('draws')
      .where('level', '==', adminLevel)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .get();

    const draws = snapshot.docs.map(doc => ({
      drawId: doc.id,
      ...doc.data()
    }));

    return res.status(200).json({
      data: draws,
      total: draws.length
    });
  } catch (error) {
    console.error('[equbs/getDraws]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/winners?level=low|medium|high
// Get all winners for a level
// ─────────────────────────────────────────────────────────────────────────────
router.get('/winners', async (req, res) => {
  try {
    const adminLevel = req.user?.level || 'low';

    const snapshot = await db.collection('users')
      .where('level', '==', adminLevel)
      .where('hasWon', '==', true)
      .orderBy('lastWinDate', 'desc')
      .get();

    const winners = snapshot.docs.map(doc => ({
      userId: doc.id,
      ...doc.data()
    }));

    return res.status(200).json({
      data: winners,
      total: winners.length
    });
  } catch (error) {
    console.error('[equbs/getWinners]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/equbs/stats?level=low|medium|high
// Get equb statistics
// ─────────────────────────────────────────────────────────────────────────────
router.get('/stats', async (req, res) => {
  try {
    const adminLevel = req.user?.level || 'low';

    const usersSnapshot = await db.collection('users')
      .where('level', '==', adminLevel)
      .where('status', '!=', 'deleted')
      .get();

    const drawsSnapshot = await db.collection('draws')
      .where('level', '==', adminLevel)
      .get();

    const users = usersSnapshot.docs.map(d => d.data());
    const activeUsers = users.filter(u => u.status === 'active').length;
    const totalWinners = users.filter(u => u.hasWon === true).length;
    const pendingDraws = users.filter(u => u.hasWon === false).length;

    return res.status(200).json({
      data: {
        level: adminLevel,
        totalUsers: users.length,
        activeUsers,
        suspendedUsers: users.filter(u => u.status === 'suspended').length,
        totalDraws: drawsSnapshot.size,
        totalWinners,
        pendingDraws,
        allWon: pendingDraws === 0
      }
    });
  } catch (error) {
    console.error('[equbs/getStats]', error);
    return res.status(500).json({ error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Helper: Fair Weighted Selection Algorithm
// ─────────────────────────────────────────────────────────────────────────────
function selectFairWinner(participants) {
  if (!participants || participants.length === 0) return null;

  // Calculate weights for each participant
  const weighted = participants.map(participant => {
    let weight = 1.0; // Base weight

    // Bonus for multiple participations (encourages consistent participation)
    // In this case, we're selecting from those who haven't won,
    // so we don't add bonus here. But in extended logic, you could track participation count.
    
    // Add random factor for fairness (prevents same person winning repeatedly)
    weight += Math.random() * 0.5;

    return { ...participant, weight };
  });

  // Sort by weight (descending)
  weighted.sort((a, b) => b.weight - a.weight);

  // Weighted random selection
  const totalWeight = weighted.reduce((sum, p) => sum + p.weight, 0);
  let random = Math.random() * totalWeight;
  let selectedWinner = null;

  for (const participant of weighted) {
    random -= participant.weight;
    if (random <= 0) {
      selectedWinner = participant;
      break;
    }
  }

  // Fallback to first (shouldn't happen, but safety)
  return selectedWinner || weighted[0];
}

module.exports = router;
