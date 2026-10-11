const express = require('express');
const pool = require('../db/pool');
const { requireKitchenOwner } = require('../middleware/auth');
const router = express.Router();

const DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const MEAL_TYPES = ['Lunch', 'Dinner'];
const FOOD_TYPES = ['Veg', 'Non-Veg', 'Both'];

function withError(url, message) {
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}error=${encodeURIComponent(message)}`;
}

router.use(requireKitchenOwner);

// Load this owner's kitchen (or send to setup) for every route below
async function loadKitchen(req, res, next) {
  const [result] = await pool.query('SELECT * FROM kitchens WHERE owner_id = ?', [req.session.user.user_id]);
  if (result.length === 0) return res.redirect('/kitchen/setup');
  req.kitchen = result[0];
  next();
}

// ---- Setup (create kitchen profile) ----
router.get('/setup', async (req, res) => {
  const [existing] = await pool.query('SELECT kitchen_id FROM kitchens WHERE owner_id = ?', [req.session.user.user_id]);
  if (existing.length > 0) return res.redirect('/kitchen');
  res.render('kitchen/setup', { title: 'TiffinRail — Set up your kitchen', error: null });
});

router.post('/setup', async (req, res) => {
  const { name, cuisine_type, location, description, food_type, image_url } = req.body;
  const rerender = (error) =>
    res.render('kitchen/setup', { title: 'TiffinRail — Set up your kitchen', error });

  if (!name || !name.trim()) return rerender('Please enter a kitchen name.');
  if (!location || !location.trim()) return rerender('Please enter a location.');
  if (food_type && !FOOD_TYPES.includes(food_type)) return rerender('Please choose a valid food type.');

  try {
    await pool.query(
      `INSERT INTO kitchens (owner_id, name, cuisine_type, location, description, food_type, image_url)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [req.session.user.user_id, name.trim(), cuisine_type, location.trim(), description, food_type || 'Veg', image_url || null]
    );
    res.redirect('/kitchen');
  } catch (err) {
    console.error(err);
    rerender('Something went wrong. Please try again.');
  }
});

// ---- Edit kitchen profile (photo, food type, description) ----
router.get('/profile', loadKitchen, (req, res) => {
  res.render('kitchen/profile', {
    title: 'TiffinRail — Edit Profile',
    kitchen: req.kitchen,
    error: null,
    breadcrumbs: [{ label: 'Dashboard', url: '/kitchen' }, { label: 'Edit Profile' }]
  });
});

router.post('/profile', loadKitchen, async (req, res) => {
  const { name, cuisine_type, location, description, food_type, image_url } = req.body;
  const rerender = (error) =>
    res.render('kitchen/profile', {
      title: 'TiffinRail — Edit Profile',
      kitchen: { ...req.kitchen, name, cuisine_type, location, description, food_type, image_url },
      error,
      breadcrumbs: [{ label: 'Dashboard', url: '/kitchen' }, { label: 'Edit Profile' }]
    });

  if (!name || !name.trim()) return rerender('Please enter a kitchen name.');
  if (!location || !location.trim()) return rerender('Please enter a location.');
  if (!FOOD_TYPES.includes(food_type)) return rerender('Please choose a valid food type.');

  try {
    await pool.query(
      `UPDATE kitchens SET name = ?, cuisine_type = ?, location = ?, description = ?,
       food_type = ?, image_url = ? WHERE kitchen_id = ?`,
      [name.trim(), cuisine_type, location.trim(), description, food_type, image_url || null, req.kitchen.kitchen_id]
    );
    res.redirect('/kitchen');
  } catch (err) {
    console.error(err);
    rerender('Something went wrong. Please try again.');
  }
});

// ---- Dashboard (uses kitchen_subscriber_summary VIEW) ----
router.get('/', loadKitchen, async (req, res) => {
  const [summary] = await pool.query(
    'SELECT * FROM kitchen_subscriber_summary WHERE kitchen_id = ?',
    [req.kitchen.kitchen_id]
  );
  res.render('kitchen/dashboard', {
    title: 'TiffinRail — Kitchen Dashboard',
    kitchen: req.kitchen,
    summary: summary[0] || null
  });
});

// ---- Weekly menu CRUD ----
router.get('/menu', loadKitchen, async (req, res) => {
  const [menuRes] = await pool.query(
    'SELECT * FROM weekly_menu WHERE kitchen_id = ? ORDER BY day_of_week, meal_type',
    [req.kitchen.kitchen_id]
  );
  const menuByDay = {};
  DAYS.forEach((d) => (menuByDay[d] = {}));
  menuRes.forEach((row) => (menuByDay[row.day_of_week][row.meal_type] = row));

  res.render('kitchen/menu', {
    title: 'TiffinRail — Weekly Menu',
    kitchen: req.kitchen,
    days: DAYS,
    menuByDay,
    breadcrumbs: [{ label: 'Dashboard', url: '/kitchen' }, { label: 'Weekly Menu' }]
  });
});

router.post('/menu', loadKitchen, async (req, res) => {
  const { day_of_week, meal_type, description } = req.body;

  if (!DAYS.includes(day_of_week) || !MEAL_TYPES.includes(meal_type)) {
    return res.redirect(withError('/kitchen/menu', 'Invalid day or meal type.'));
  }
  if (!description || !description.trim()) {
    return res.redirect(withError('/kitchen/menu', "Menu description can't be empty."));
  }

  try {
    await pool.query(
      `INSERT INTO weekly_menu (kitchen_id, day_of_week, meal_type, description)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE description = VALUES(description)`,
      [req.kitchen.kitchen_id, day_of_week, meal_type, description.trim().slice(0, 300)]
    );
    res.redirect('/kitchen/menu');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/kitchen/menu', "Couldn't save that menu item. Please try again."));
  }
});

// ---- Subscription plans CRUD ----
router.get('/plans', loadKitchen, async (req, res) => {
  const [plans] = await pool.query(
    'SELECT * FROM subscription_plans WHERE kitchen_id = ? ORDER BY duration_days, price',
    [req.kitchen.kitchen_id]
  );
  res.render('kitchen/plans', {
    title: 'TiffinRail — Subscription Plans',
    kitchen: req.kitchen,
    plans: plans,
    breadcrumbs: [{ label: 'Dashboard', url: '/kitchen' }, { label: 'Plans' }]
  });
});

router.post('/plans', loadKitchen, async (req, res) => {
  const { name, duration_days, meals_per_day, price } = req.body;
  const durationNum = parseInt(duration_days, 10);
  const mealsNum = parseInt(meals_per_day, 10);
  const priceNum = parseFloat(price);

  if (!name || !name.trim()) {
    return res.redirect(withError('/kitchen/plans', 'Please enter a plan name.'));
  }
  if (![7, 30].includes(durationNum)) {
    return res.redirect(withError('/kitchen/plans', 'Duration must be 7 (weekly) or 30 (monthly) days.'));
  }
  if (![1, 2].includes(mealsNum)) {
    return res.redirect(withError('/kitchen/plans', 'Meals per day must be 1 or 2.'));
  }
  if (!priceNum || priceNum <= 0) {
    return res.redirect(withError('/kitchen/plans', 'Price must be a positive number.'));
  }

  try {
    await pool.query(
      `INSERT INTO subscription_plans (kitchen_id, name, duration_days, meals_per_day, price)
       VALUES (?, ?, ?, ?, ?)`,
      [req.kitchen.kitchen_id, name.trim(), durationNum, mealsNum, priceNum]
    );
    res.redirect('/kitchen/plans');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/kitchen/plans', "Couldn't create that plan. Please try again."));
  }
});

router.post('/plans/:id/toggle', loadKitchen, async (req, res) => {
  try {
    await pool.query(
      'UPDATE subscription_plans SET active = NOT active WHERE plan_id = ? AND kitchen_id = ?',
      [req.params.id, req.kitchen.kitchen_id]
    );
    res.redirect('/kitchen/plans');
  } catch (err) {
    console.error(err);
    res.redirect(withError('/kitchen/plans', "Couldn't update that plan. Please try again."));
  }
});

// ---- Subscribers list ----
router.get('/subscribers', loadKitchen, async (req, res) => {
  const [subs] = await pool.query(
    `SELECT s.*, u.name AS student_name, u.phone, p.name AS plan_name
     FROM subscriptions s
     JOIN users u ON u.user_id = s.student_id
     JOIN subscription_plans p ON p.plan_id = s.plan_id
     WHERE s.kitchen_id = ? ORDER BY s.created_at DESC`,
    [req.kitchen.kitchen_id]
  );
  res.render('kitchen/subscribers', {
    title: 'TiffinRail — Subscribers',
    kitchen: req.kitchen,
    subs: subs,
    breadcrumbs: [{ label: 'Dashboard', url: '/kitchen' }, { label: 'Subscribers' }]
  });
});

module.exports = router;
