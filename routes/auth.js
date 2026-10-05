const express = require('express');
const bcrypt = require('bcryptjs');
const pool = require('../db/pool');
const router = express.Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Only allow redirecting back to a path on our own site (never an external URL)
function safeRedirect(target) {
  return typeof target === 'string' && target.startsWith('/') && !target.startsWith('//') ? target : null;
}

router.get('/signup', (req, res) => {
  res.render('signup', {
    title: 'TiffinRail — Sign Up',
    error: null,
    redirect: req.query.redirect || ''
  });
});

router.post('/signup', async (req, res) => {
  const { name, email, password, phone, address, role, redirect } = req.body;

  const rerender = (error) =>
    res.render('signup', { title: 'TiffinRail — Sign Up', error, redirect: redirect || '' });

  if (!['student', 'kitchen_owner'].includes(role)) {
    return rerender('Please choose a valid account type.');
  }
  if (!name || !name.trim()) {
    return rerender('Please enter your name.');
  }
  if (!email || !EMAIL_RE.test(email.trim())) {
    return rerender('Please enter a valid email address.');
  }
  if (!password || password.length < 6) {
    return rerender('Password must be at least 6 characters.');
  }
  if (phone && phone.trim() && !/^\d{10}$/.test(phone.trim())) {
    return rerender('Phone number should be exactly 10 digits (or leave it blank).');
  }

  try {
    const existing = await pool.query('SELECT user_id FROM users WHERE email = $1', [email.trim().toLowerCase()]);
    if (existing.rows.length > 0) {
      return rerender('An account with that email already exists.');
    }
    const hash = await bcrypt.hash(password, 10);
    const result = await pool.query(
      `INSERT INTO users (name, email, password_hash, phone, address, role)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING user_id, name, role`,
      [name.trim(), email.trim().toLowerCase(), hash, phone ? phone.trim() : null, address, role]
    );
    req.session.user = result.rows[0];

    if (role === 'kitchen_owner') {
      return res.redirect('/kitchen/setup');
    }
    const safe = safeRedirect(redirect);
    res.redirect(safe || '/');
  } catch (err) {
    console.error(err);
    rerender('Something went wrong. Please try again.');
  }
});

router.get('/login', (req, res) => {
  res.render('login', {
    title: 'TiffinRail — Login',
    error: null,
    redirect: req.query.redirect || ''
  });
});

router.post('/login', async (req, res) => {
  const { email, password, redirect } = req.body;
  const rerender = (error) =>
    res.render('login', { title: 'TiffinRail — Login', error, redirect: redirect || '' });

  if (!email || !password) {
    return rerender('Please enter both email and password.');
  }

  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email.trim().toLowerCase()]);
    const user = result.rows[0];
    if (!user) return rerender('Invalid email or password.');

    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) return rerender('Invalid email or password.');

    req.session.user = { user_id: user.user_id, name: user.name, role: user.role };

    const safe = safeRedirect(redirect);
    if (safe) return res.redirect(safe);

    if (user.role === 'kitchen_owner') {
      const kitchen = await pool.query('SELECT kitchen_id FROM kitchens WHERE owner_id = $1', [user.user_id]);
      return res.redirect(kitchen.rows.length ? '/kitchen' : '/kitchen/setup');
    }
    if (user.role === 'admin') {
      return res.redirect('/admin');
    }
    res.redirect('/');
  } catch (err) {
    console.error(err);
    rerender('Something went wrong. Please try again.');
  }
});

router.post('/logout', (req, res) => {
  req.session.destroy(() => res.redirect('/login'));
});

module.exports = router;
