require('dotenv').config();
const express = require('express');
const session = require('express-session');
const pgSession = require('connect-pg-simple')(session);
const path = require('path');
const pool = require('./db/pool');

const authRoutes = require('./routes/auth');
const studentRoutes = require('./routes/student');
const kitchenRoutes = require('./routes/kitchen');
const adminRoutes = require('./routes/admin');

const app = express();
const PORT = process.env.PORT || 3000;

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.use(
  session({
    store: new pgSession({
      pool,
      tableName: 'user_sessions',
      createTableIfMissing: true
    }),
    secret: process.env.SESSION_SECRET || 'dev-secret-change-this',
    resave: false,
    saveUninitialized: false,
    cookie: { maxAge: 1000 * 60 * 60 * 4 }
  })
);

app.use((req, res, next) => {
  res.locals.user = req.session.user || null;
  res.locals.errorMsg = req.query.error || null;
  res.locals.successMsg = req.query.success || null;
  next();
});

app.use('/', authRoutes);
app.use('/', studentRoutes);
app.use('/kitchen', kitchenRoutes);
app.use('/admin', adminRoutes);

app.use((req, res) => {
  res.status(404).render('404', { title: 'TiffinRail — Page Not Found' });
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});

module.exports = app;
