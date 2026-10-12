# TiffinRail v4 — Tiffin/Mess Subscription Marketplace (MySQL)

**Live demo:** https://tiffin-rail.onrender.com

A DBMS mini-project: kitchen/mess owners list their weekly menu and subscription plans; students browse and subscribe weekly or monthly, instead of one-off ordering.

## What it demonstrates

| DBMS concept | Where |
|---|---|
| Normalized schema (BCNF in 8 of 9 tables; `subscriptions.kitchen_id` is a documented denormalization) | `db/schema.sql` — 9 tables on the InnoDB engine, with PK / FK / UNIQUE / CHECK constraints |
| Relationships | 1:1 (owner↔kitchen), 1:M (kitchen→weekly_menu, kitchen→plans, student→subscriptions), M:M in spirit (students subscribe to many kitchens' plans) |
| Triggers | `trg_validate_subscription_status` — blocks illegal status jumps (e.g. Cancelled → Active) using `SIGNAL`; `trg_auto_expire` — flips a subscription to Expired the moment its end_date passes. Both are `BEFORE UPDATE` on `subscriptions`; the first is declared `FOLLOWS` the second so the order is guaranteed |
| View | `kitchen_subscriber_summary` — active subscriber count + revenue per kitchen, powers the owner's dashboard |
| Stored procedures | `subscribe_student` — creates a subscription + payment atomically (`START TRANSACTION` … `COMMIT`, with an exit handler that `ROLLBACK`s on any error); `pause_subscription` — extends `end_date` by N days and logs the pause. Called from Node with `CALL` |
| Transactions/ACID | Subscribing is one atomic operation — if anything fails, no partial subscription/payment is left behind |
| Two-sided CRUD | Kitchen owners manage their own menu/plans; students manage (pause/resume/cancel) their own subscriptions |
| Session persistence | Sessions are stored in MySQL via `express-mysql-session` (auto-creates a `user_sessions` table), not in server memory — logins survive a server restart, which matters once this is deployed |
| Reviews + derived data | `reviews` table with three triggers (`trg_refresh_rating_insert/update/delete` — MySQL needs one trigger per event) that recalculate `kitchens.rating` as the live average whenever a review is added, edited, or deleted |
| Business model / commission | `kitchen_subscriber_summary` view now computes `platform_commission` and `net_payout` per kitchen from a per-kitchen `commission_percent` field |
| Platform-level admin | `platform_overview` view aggregates gross revenue, commission earned, verified kitchens, and reported reviews across the whole platform — a third role (`admin`) sits above students/kitchen owners |

## Two account types

- **Student** — browses kitchens, views weekly menus and plans, subscribes, can pause/resume/cancel.
- **Kitchen owner** — one kitchen per owner. Sets weekly menu (7 days × Lunch/Dinner), creates subscription plans, sees subscriber list and a revenue dashboard.

## Project structure

```
tiffin-rail/
├── server.js
├── db/
│   ├── schema.sql       # tables, triggers, views, stored procedures, sample data (MySQL 8)
│   ├── seed.js          # runs schema.sql, then sets demo + admin passwords
│   └── pool.js          # mysql2 connection pool
├── middleware/auth.js
├── routes/               # auth.js, student.js, kitchen.js, admin.js
├── views/
│   ├── kitchen/          # kitchen-owner-only pages
│   └── partials/
└── public/css/style.css
```

## Run it locally

Requires Node.js 18+ and **MySQL 8.0.16 or newer** (older versions parse but silently ignore `CHECK` constraints).

```bash
npm install
cp .env.example .env      # then edit .env with your MySQL password AND your admin login
mysql -u root -p -e "CREATE DATABASE tiffin_rail CHARACTER SET utf8mb4;"
node db/seed.js
npm start
```
Visit `http://localhost:3000`.

You can also load the schema without Node — in MySQL Workbench open `db/schema.sql` and run it against the `tiffin_rail` database, or from a terminal: `mysql -u root -p tiffin_rail < db/schema.sql` (run `node db/seed.js` afterwards so the demo accounts get working passwords).

**Troubleshooting — `ERROR 1419 ... SUPER privilege and binary logging is enabled`:** this appears when a non-root MySQL user creates triggers/procedures on a server with binary logging on. Either run the schema as `root`, or have an admin run `SET GLOBAL log_bin_trust_function_creators = 1;`. Many hosted MySQL services already allow this.

**Admin login:** set `ADMIN_EMAIL` and `ADMIN_PASSWORD` in your `.env` file before running `node db/seed.js` — this is the only account with access to `/admin`, and it's never shown anywhere on the site. If you skip this, the seed script warns you and the admin account is left unusable until you set it and re-run the seed.

**Demo logins for local testing only** (never shown on the live site):
- `sunita@ghar.com` / `owner123` — kitchen owner (Ghar Ka Khana)
- `ramesh@tiffin.com` / `owner123` — kitchen owner (Ramesh Tiffin Service)
- `aman@student.com` / `student123` — student (has sample reviews already posted)
- `priya@student.com` / `student123` — student (has sample reviews already posted)

Or sign up as a new student/kitchen owner from the homepage.

## How kitchen approval works
New kitchens don't go live automatically. When someone signs up as a kitchen owner and fills out their kitchen profile, it's created with `approval_status = 'pending'` — invisible to students, but the owner can still preview it and set up their menu/plans. Log in as admin, go to the **Platform Dashboard**, and use the **Pending kitchen approvals** section to approve or reject it. Only approved kitchens show up in search/browse.

## Before you deploy or submit
Open `views/partials/footer.ejs` and replace the placeholder email/phone in the "Contact admin" section with your real details.

The two demo kitchen photos are real, freely-licensed (CC BY-SA) photos from Wikimedia Commons — fine for a demo/viva. For a real deployment, each kitchen owner should replace these with their own photo via **Kitchen Dashboard → Edit profile → Photo URL**.

## Deploy
Create a MySQL 8 database on any host, then set `DATABASE_URL=mysql://user:password@host:3306/dbname` (and `DB_SSL=true` if the host requires TLS) as environment variables on the app host. Run `node db/seed.js` once to create the tables and demo data.
