const express = require('express');
const pool = require('../db/pool');
const { requireAdmin } = require('../middleware/auth');
const router = express.Router();

function withError(url, message) {
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}error=${encodeURIComponent(message)}`;
}

router.use(requireAdmin);

// Platform-wide dashboard (uses the platform_overview VIEW)
router.get('/', async (req, res) => {
  const overview = await pool.query('SELECT * FROM platform_overview');
  const kitchens = await pool.query(
    `SELECT s.* FROM kitchen_subscriber_summary s
     JOIN kitchens k ON k.kitchen_id = s.kitchen_id
     WHERE k.approval_status = 'approved'
     ORDER BY s.total_revenue DESC`
  );
  const kitchenMeta = await pool.query(
    'SELECT kitchen_id, is_verified, commission_percent, approval_status FROM kitchens'
  );
  const metaMap = {};
  kitchenMeta.rows.forEach((k) => (metaMap[k.kitchen_id] = k));

  const pendingKitchens = await pool.query(
    `SELECT k.*, u.name AS owner_name, u.email AS owner_email, u.phone AS owner_phone
     FROM kitchens k
     JOIN users u ON u.user_id = k.owner_id
     WHERE k.approval_status = 'pending'
     ORDER BY k.created_at ASC`
  );

  const reportedReviews = await pool.query(
    `SELECT r.*, k.name AS kitchen_name, u.name AS student_name
     FROM reviews r
     JOIN kitchens k ON k.kitchen_id = r.kitchen_id
     JOIN users u ON u.user_id = r.student_id
     WHERE r.reported = TRUE ORDER BY r.created_at DESC`
  );

  res.render('admin/dashboard', {
    title: 'TiffinRail — Platform Dashboard',
    overview: overview.rows[0],
    kitchens: kitchens.rows,
    metaMap,
    pendingKitchens: pendingKitchens.rows,
    reportedReviews: reportedReviews.rows
  });
});

// Approve a pending kitchen — makes it visible on the public site
router.post('/kitchen/:id/approve', async (req, res) => {
  try {
    await pool.query("UPDATE kitchens SET approval_status = 'approved' WHERE kitchen_id = $1", [req.params.id]);
    res.redirect('/admin');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/admin', "Couldn't approve that kitchen."));
  }
});

// Reject a pending kitchen — stays hidden from students
router.post('/kitchen/:id/reject', async (req, res) => {
  try {
    await pool.query("UPDATE kitchens SET approval_status = 'rejected' WHERE kitchen_id = $1", [req.params.id]);
    res.redirect('/admin');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/admin', "Couldn't reject that kitchen."));
  }
});

// Toggle a kitchen's verified badge
router.post('/kitchen/:id/verify-toggle', async (req, res) => {
  try {
    await pool.query('UPDATE kitchens SET is_verified = NOT is_verified WHERE kitchen_id = $1', [req.params.id]);
    res.redirect('/admin');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/admin', "Couldn't update verification status."));
  }
});

// Update a kitchen's commission percentage
router.post('/kitchen/:id/commission', async (req, res) => {
  const commissionNum = parseFloat(req.body.commission_percent);
  if (isNaN(commissionNum) || commissionNum < 0 || commissionNum > 100) {
    return res.redirect(withError('/admin', 'Commission must be a number between 0 and 100.'));
  }
  try {
    await pool.query('UPDATE kitchens SET commission_percent = $1 WHERE kitchen_id = $2', [
      commissionNum,
      req.params.id
    ]);
    res.redirect('/admin');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/admin', "Couldn't update commission rate."));
  }
});

// Dismiss a reported review (keeps it, just clears the flag)
router.post('/review/:id/dismiss', async (req, res) => {
  try {
    await pool.query('UPDATE reviews SET reported = FALSE WHERE review_id = $1', [req.params.id]);
    res.redirect('/admin');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/admin', "Couldn't dismiss that report."));
  }
});

// Delete a reported review entirely
router.post('/review/:id/delete', async (req, res) => {
  try {
    await pool.query('DELETE FROM reviews WHERE review_id = $1', [req.params.id]);
    res.redirect('/admin');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/admin', "Couldn't delete that review."));
  }
});

module.exports = router;
