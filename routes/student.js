const express = require('express');
const pool = require('../db/pool');
const { requireLogin, requireStudent } = require('../middleware/auth');
const router = express.Router();

const DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];

function withError(url, message) {
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}error=${encodeURIComponent(message)}`;
}

function withSuccess(url, message) {
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}success=${encodeURIComponent(message)}`;
}

// Home: welcoming landing page with kitchen list, search, and cuisine filter
router.get('/', async (req, res) => {
  const search = req.query.q || '';
  const cuisine = req.query.cuisine || '';

  let query = `
    SELECT k.*, COUNT(s.subscription_id) FILTER (WHERE s.status = 'Active') AS active_subscribers
    FROM kitchens k
    LEFT JOIN subscriptions s ON s.kitchen_id = k.kitchen_id
    WHERE k.approval_status = 'approved' AND (k.name ILIKE $1 OR k.location ILIKE $1 OR k.cuisine_type ILIKE $1)`;
  const params = [`%${search}%`];

  if (cuisine) {
    query += ` AND k.cuisine_type = $2`;
    params.push(cuisine);
  }
  query += ` GROUP BY k.kitchen_id ORDER BY k.rating DESC`;

  const result = await pool.query(query, params);
  const cuisinesRes = await pool.query(
    "SELECT DISTINCT cuisine_type FROM kitchens WHERE cuisine_type IS NOT NULL AND approval_status = 'approved' ORDER BY cuisine_type"
  );

  let favoriteIds = [];
  if (req.session.user && req.session.user.role === 'student') {
    const favRes = await pool.query('SELECT kitchen_id FROM favorites WHERE student_id = $1', [
      req.session.user.user_id
    ]);
    favoriteIds = favRes.rows.map((r) => r.kitchen_id);
  }

  const testimonialsRes = await pool.query(
    `SELECT r.rating, r.comment, u.name AS student_name, k.name AS kitchen_name
     FROM reviews r
     JOIN users u ON u.user_id = r.student_id
     JOIN kitchens k ON k.kitchen_id = r.kitchen_id
     WHERE r.comment IS NOT NULL AND r.rating >= 4
     ORDER BY r.rating DESC, r.created_at DESC
     LIMIT 6`
  );

  // Spotlight: the single highest-rated approved kitchen with at least one review
  const featuredRes = await pool.query(
    `SELECT k.*, COUNT(s.subscription_id) FILTER (WHERE s.status = 'Active') AS active_subscribers
     FROM kitchens k
     LEFT JOIN subscriptions s ON s.kitchen_id = k.kitchen_id
     WHERE k.approval_status = 'approved' AND k.rating > 0
     GROUP BY k.kitchen_id
     ORDER BY k.rating DESC, k.created_at DESC
     LIMIT 1`
  );

  // Platform stats for the "trusted by" strip (only counts approved kitchens)
  const statsRes = await pool.query(`
    SELECT
      (SELECT COUNT(*) FROM kitchens WHERE approval_status = 'approved') AS kitchen_count,
      (SELECT COUNT(*) FROM users WHERE role = 'student') AS student_count,
      (SELECT ROUND(AVG(rating), 1) FROM kitchens WHERE approval_status = 'approved' AND rating > 0) AS avg_rating
  `);

  res.render('home', {
    title: 'TiffinRail — Find your mess',
    kitchens: result.rows,
    search,
    cuisine,
    cuisines: cuisinesRes.rows.map((r) => r.cuisine_type),
    favoriteIds,
    testimonials: testimonialsRes.rows,
    featured: featuredRes.rows[0] || null,
    stats: statsRes.rows[0]
  });
});

// Toggle favorite (works from home grid or kitchen detail page)
router.post('/favorite/:kitchen_id/toggle', requireStudent, async (req, res) => {
  const { kitchen_id } = req.params;
  const studentId = req.session.user.user_id;
  const back = req.get('Referrer') || '/';
  try {
    const existing = await pool.query(
      'SELECT favorite_id FROM favorites WHERE student_id = $1 AND kitchen_id = $2',
      [studentId, kitchen_id]
    );
    if (existing.rows.length > 0) {
      await pool.query('DELETE FROM favorites WHERE student_id = $1 AND kitchen_id = $2', [studentId, kitchen_id]);
    } else {
      await pool.query('INSERT INTO favorites (student_id, kitchen_id) VALUES ($1, $2)', [studentId, kitchen_id]);
    }
    res.redirect(back);
  } catch (err) {
    console.error(err);
    res.redirect(withError(back, "Couldn't update favorites. Please try again."));
  }
});

// My favorites page
router.get('/favorites', requireStudent, async (req, res) => {
  const result = await pool.query(
    `SELECT k.*, COUNT(s.subscription_id) FILTER (WHERE s.status = 'Active') AS active_subscribers
     FROM favorites f
     JOIN kitchens k ON k.kitchen_id = f.kitchen_id
     LEFT JOIN subscriptions s ON s.kitchen_id = k.kitchen_id
     WHERE f.student_id = $1
     GROUP BY k.kitchen_id
     ORDER BY f.created_at DESC`,
    [req.session.user.user_id]
  );
  res.render('favorites', {
    title: 'TiffinRail — My Favorites',
    kitchens: result.rows,
    breadcrumbs: [{ label: 'Home', url: '/' }, { label: 'My Favorites' }]
  });
});

// Kitchen detail: weekly menu + plans
router.get('/kitchen-detail/:id', async (req, res) => {
  const { id } = req.params;
  const kitchen = await pool.query('SELECT * FROM kitchens WHERE kitchen_id = $1', [id]);
  if (kitchen.rows.length === 0) return res.status(404).render('404', { title: 'TiffinRail — Not Found' });

  const isOwner = req.session.user && req.session.user.user_id === kitchen.rows[0].owner_id;
  const isAdmin = req.session.user && req.session.user.role === 'admin';
  if (kitchen.rows[0].approval_status !== 'approved' && !isOwner && !isAdmin) {
    return res.status(404).render('404', { title: 'TiffinRail — Not Found' });
  }

  const menuRes = await pool.query(
    'SELECT * FROM weekly_menu WHERE kitchen_id = $1 ORDER BY day_of_week, meal_type',
    [id]
  );
  const plansRes = await pool.query(
    'SELECT * FROM subscription_plans WHERE kitchen_id = $1 AND active = TRUE ORDER BY price',
    [id]
  );
  const reviewsRes = await pool.query(
    `SELECT r.*, u.name AS student_name FROM reviews r
     JOIN users u ON u.user_id = r.student_id
     WHERE r.kitchen_id = $1 ORDER BY r.created_at DESC`,
    [id]
  );

  let myReview = null;
  let isFavorited = false;
  if (req.session.user && req.session.user.role === 'student') {
    const mine = await pool.query(
      'SELECT * FROM reviews WHERE kitchen_id = $1 AND student_id = $2',
      [id, req.session.user.user_id]
    );
    myReview = mine.rows[0] || null;

    const favCheck = await pool.query(
      'SELECT 1 FROM favorites WHERE kitchen_id = $1 AND student_id = $2',
      [id, req.session.user.user_id]
    );
    isFavorited = favCheck.rows.length > 0;
  }

  // Group menu by day for the template
  const menuByDay = {};
  DAYS.forEach((d) => (menuByDay[d] = {}));
  menuRes.rows.forEach((row) => {
    menuByDay[row.day_of_week][row.meal_type] = row.description;
  });

  res.render('kitchen_detail', {
    title: `TiffinRail — ${kitchen.rows[0].name}`,
    kitchen: kitchen.rows[0],
    days: DAYS,
    menuByDay,
    plans: plansRes.rows,
    reviews: reviewsRes.rows,
    myReview,
    isFavorited,
    breadcrumbs: [{ label: 'Home', url: '/' }, { label: kitchen.rows[0].name }]
  });
});

// Post or update a review (one per student per kitchen)
router.post('/kitchen-detail/:id/review', requireStudent, async (req, res) => {
  const { rating, comment } = req.body;
  const detailUrl = `/kitchen-detail/${req.params.id}`;
  const ratingNum = parseInt(rating, 10);

  if (!ratingNum || ratingNum < 1 || ratingNum > 5) {
    return res.redirect(withError(detailUrl, 'Please choose a rating between 1 and 5.'));
  }

  try {
    await pool.query(
      `INSERT INTO reviews (kitchen_id, student_id, rating, comment)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (kitchen_id, student_id)
       DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, created_at = NOW()`,
      [req.params.id, req.session.user.user_id, ratingNum, comment ? comment.trim().slice(0, 500) : null]
    );
    res.redirect(detailUrl);
  } catch (err) {
    console.error(err);
    res.redirect(withError(detailUrl, "Couldn't save your review. Please try again."));
  }
});

// Report a review as inappropriate/fake — flags it for admin moderation
router.post('/review/:review_id/report', requireStudent, async (req, res) => {
  const back = req.get('Referrer') || '/';
  try {
    await pool.query('UPDATE reviews SET reported = TRUE WHERE review_id = $1', [req.params.review_id]);
    res.redirect(withSuccess(back, 'Thanks — this review has been reported to our team.'));
  } catch (err) {
    console.error(err);
    res.redirect(withError(back, "Couldn't report this review. Please try again."));
  }
});

// Subscribe to a plan (uses subscribe_student() Postgres function)
router.post('/subscribe/:plan_id', requireStudent, async (req, res) => {
  const back = req.get('Referrer') || '/';
  try {
    const result = await pool.query('SELECT subscribe_student($1, $2) AS subscription_id', [
      req.session.user.user_id,
      req.params.plan_id
    ]);
    res.redirect(`/my-subscriptions?subscribed=${result.rows[0].subscription_id}`);
  } catch (err) {
    console.error(err);
    res.redirect(withError(back, 'Could not subscribe — this plan may no longer be available.'));
  }
});

// My subscriptions
router.get('/my-subscriptions', requireStudent, async (req, res) => {
  // Opportunistically flip any past-due subscriptions to Expired
  await pool.query(
    `UPDATE subscriptions SET status = 'Expired'
     WHERE student_id = $1 AND status = 'Active' AND end_date < CURRENT_DATE`,
    [req.session.user.user_id]
  );

  const subs = await pool.query(
    `SELECT s.*, k.name AS kitchen_name, p.name AS plan_name, p.price,
            (s.end_date - CURRENT_DATE) AS days_left
     FROM subscriptions s
     JOIN kitchens k ON k.kitchen_id = s.kitchen_id
     JOIN subscription_plans p ON p.plan_id = s.plan_id
     WHERE s.student_id = $1 ORDER BY s.created_at DESC`,
    [req.session.user.user_id]
  );
  res.render('my_subscriptions', {
    title: 'TiffinRail — My Subscriptions',
    subs: subs.rows,
    subscribed: req.query.subscribed || null,
    breadcrumbs: [{ label: 'Home', url: '/' }, { label: 'My Subscriptions' }]
  });
});

router.post('/subscription/:id/pause', requireStudent, async (req, res) => {
  const days = parseInt(req.body.days, 10);
  const reason = req.body.reason ? req.body.reason.trim().slice(0, 255) : null;

  if (!days || days < 1 || days > 14) {
    return res.redirect(withError('/my-subscriptions', 'Pause length must be between 1 and 14 days.'));
  }

  try {
    await pool.query('SELECT pause_subscription($1, $2, $3)', [req.params.id, days, reason]);
    res.redirect('/my-subscriptions');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/my-subscriptions', 'Could not pause this subscription. It may already be paused or ended.'));
  }
});

router.post('/subscription/:id/resume', requireStudent, async (req, res) => {
  try {
    await pool.query(
      `UPDATE subscriptions SET status = 'Active' WHERE subscription_id = $1 AND student_id = $2`,
      [req.params.id, req.session.user.user_id]
    );
    res.redirect('/my-subscriptions');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/my-subscriptions', 'Could not resume this subscription.'));
  }
});

router.post('/subscription/:id/cancel', requireStudent, async (req, res) => {
  try {
    await pool.query(
      `UPDATE subscriptions SET status = 'Cancelled' WHERE subscription_id = $1 AND student_id = $2`,
      [req.params.id, req.session.user.user_id]
    );
    res.redirect('/my-subscriptions');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/my-subscriptions', 'Could not cancel this subscription.'));
  }
});

module.exports = router;
