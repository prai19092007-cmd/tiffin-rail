# TiffinRail — Tiffin/Mess Subscription Marketplace

A full-stack DBMS project: kitchen/mess owners list their weekly menu and subscription plans; students browse nearby kitchens and subscribe weekly or monthly, instead of ordering food one meal at a time. A platform admin approves new kitchens before they go live and takes a commission on each subscription.

**Live demo:** https://tiffin-rail.onrender.com

**Source code:** https://github.com/prai19092007-cmd/tiffin-rail

## What it demonstrates 

| DBMS concept | Where |
|---|---|
| Normalized schema (3NF) | `db/schema.sql` — 9 tables |
| Relationships | 1:1 (owner↔kitchen), 1:M (kitchen→weekly_menu, kitchen→plans, student→subscriptions, student→reviews/favorites) |
| Triggers | `trg_validate_subscription_status` — blocks illegal status jumps (e.g. Cancelled → Active); `trg_auto_expire` — flips a subscription to Expired once its end_date passes; `trg_refresh_rating_insert` — recalculates a kitchen's star rating live whenever a review is added, edited, or deleted |
| Views | `kitchen_subscriber_summary` — active subscribers, revenue, commission, and net payout per kitchen; `platform_overview` — platform-wide totals for the admin dashboard |
| Stored procedures | `subscribe_student()` — creates a subscription + payment atomically; `pause_subscription()` — extends `end_date` by N days and logs the pause |
| Transactions/ACID | Subscribing is one atomic operation — if anything fails, no partial subscription/payment is left behind |
| Three-way role separation | Students, kitchen owners, and a single private platform admin each see only what's relevant to them |
| Session persistence | Sessions are stored in Postgres via `connect-pg-simple` (auto-creates a `user_sessions` table), not in server memory — logins survive a server restart |
| Business model | Per-kitchen `commission_percent`, computed gross revenue, platform commission, and owner payout — all calculated inside the database, not in application code |

## Three account types

- **Student** — browses kitchens, views weekly menus and plans, subscribes, can pause/resume/cancel, favorites kitchens, leaves reviews.
- **Kitchen owner** — one kitchen per owner. Sets a weekly menu (7 days x Lunch/Dinner), creates subscription plans, sees subscriber list and a revenue dashboard. New kitchens start as "pending" and are invisible to students until approved.
- **Platform admin** — a single private account (see below). Approves/rejects new kitchens, sets each kitchen's commission rate, verifies kitchens, moderates reported reviews.

## Project structure

```
tiffin-rail/
├── server.js
├── db/
│   ├── schema.sql       # tables, triggers, views, stored procedures, sample data
│   ├── seed.js
│   └── pool.js
├── middleware/auth.js
├── routes/               # auth.js, student.js, kitchen.js, admin.js
├── views/
│   ├── kitchen/          # kitchen-owner-only pages
│   ├── admin/            # admin-only pages
│   └── partials/
└── public/css/style.css
```

## Run it locally

```bash
npm install
cp .env.example .env      # edit .env: your local Postgres password, plus ADMIN_EMAIL and ADMIN_PASSWORD
createdb tiffin_rail
node db/seed.js
npm start
```
Visit `http://localhost:3000`.

**Admin login:** set `ADMIN_EMAIL` and `ADMIN_PASSWORD` in `.env` before running `node db/seed.js` — this is the only account with access to `/admin`, and it is never shown anywhere on the site itself. If you skip this, the seed script warns you and leaves the admin account unusable until you set it and re-run the seed.

**Demo logins for local testing only** (never shown on the live site):
- `sunita@ghar.com` / `owner123` — kitchen owner (Ghar Ka Khana)
- `ramesh@tiffin.com` / `owner123` — kitchen owner (Ramesh Tiffin Service)
- `aman@student.com` / `student123` — student (has sample reviews already posted)
- `priya@student.com` / `student123` — student (has sample reviews already posted)

Or sign up as a new student/kitchen owner from the homepage.

## How kitchen approval works
New kitchens don't go live automatically. When someone signs up as a kitchen owner and fills out their kitchen profile, it's created with `approval_status = 'pending'` — invisible to students, though the owner can preview it and set up their menu/plans while waiting. Log in as admin, open the **Platform Dashboard**, and use **Pending kitchen approvals** to approve or reject it. Only approved kitchens appear in search/browse.

## Deploying to Render (free tier)

This project is already deployed this way — here's the real process, including the two gotchas you'll likely hit.

1. **Push the code to GitHub** (a private repo is fine). Make sure `.env` is *not* included — `.gitignore` already excludes it.
2. **Create a free PostgreSQL database on Render** (Dashboard → New → PostgreSQL). Copy its *Internal* Database URL (for the web service) and its *External* Database URL (for seeding from your own computer).
3. **Create a free Web Service on Render**, connected to your GitHub repo. Build command: `npm install`. Start command: `npm start`. Add environment variables: `DATABASE_URL` (the Internal URL), `SESSION_SECRET` (any long random string), `ADMIN_EMAIL`, `ADMIN_PASSWORD`.
4. **Seed the live database from your own machine** — free Render web services don't have shell access, so you can't run the seed script "on" Render itself. Instead, point your local seed script at the database's *External* URL temporarily:
   ```powershell
   $env:DATABASE_URL="<external-database-url>?sslmode=require"; $env:ADMIN_EMAIL="you@example.com"; $env:ADMIN_PASSWORD="yourpassword"; node --dns-result-order=ipv4first db/seed.js
   ```
   Two flags matter here and will save you a lot of debugging: `--dns-result-order=ipv4first` avoids an `ECONNRESET` some networks hit over IPv6, and `?sslmode=require` on the URL is required by Render Postgres.
5. **Redeploy** the web service (Manual Deploy → Deploy latest commit) once the database is seeded, so it stops crashing on the now-existing tables.
6. Free-tier web services sleep after 15 minutes of no traffic and take 30-60 seconds to wake back up on the next visit — open the live link a couple of minutes before a demo to "warm it up." Free databases expire 30 days after creation (14-day grace period) — recreate and reseed if needed closer to a later demo.

## Before you deploy or submit
Open `views/partials/footer.ejs` and confirm the email/phone in the "Contact admin" section are the details you actually want public.

