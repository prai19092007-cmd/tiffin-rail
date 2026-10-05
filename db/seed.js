// Run with: node db/seed.js
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const pool = require('./pool');

// Your real admin login — set these in .env, never hardcoded or shown on the site.
const ADMIN_EMAIL = process.env.ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

async function seed() {
  const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  console.log('Running schema.sql ...');
  await pool.query(schema);

  const ownerHash = await bcrypt.hash('owner123', 10);
  await pool.query('UPDATE users SET password_hash = $1 WHERE role = $2', [ownerHash, 'kitchen_owner']);

  const studentHash = await bcrypt.hash('student123', 10);
  await pool.query('UPDATE users SET password_hash = $1 WHERE role = $2', [studentHash, 'student']);

  if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
    console.warn('');
    console.warn('⚠️  ADMIN_EMAIL / ADMIN_PASSWORD are not set in your .env file.');
    console.warn('   The seeded admin account still has its placeholder password and cannot log in.');
    console.warn('   Add these two lines to .env, then re-run node db/seed.js:');
    console.warn('     ADMIN_EMAIL=your-real-email@example.com');
    console.warn('     ADMIN_PASSWORD=choose-a-strong-password');
    console.warn('');
  } else {
    const adminHash = await bcrypt.hash(ADMIN_PASSWORD, 10);
    await pool.query(
      'UPDATE users SET email = $1, password_hash = $2 WHERE role = $3',
      [ADMIN_EMAIL.trim().toLowerCase(), adminHash, 'admin']
    );
  }

  console.log('Database seeded successfully.');
  console.log('Demo kitchen owner logins (local testing only):');
  console.log('  sunita@ghar.com / owner123   (Ghar Ka Khana)');
  console.log('  ramesh@tiffin.com / owner123 (Ramesh Tiffin Service)');
  console.log('Demo student logins (local testing only):');
  console.log('  aman@student.com / student123');
  console.log('  priya@student.com / student123');
  if (ADMIN_EMAIL && ADMIN_PASSWORD) {
    console.log(`Admin login: ${ADMIN_EMAIL} (password set from your .env file)`);
  }
  console.log('None of these are shown anywhere on the live site — this is local console output only.');
  await pool.end();
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
