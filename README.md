# TiffinRail v2 — Tiffin/Mess Subscription Marketplace

A DBMS mini-project: kitchen/mess owners list their weekly menu and subscription plans; students browse and subscribe weekly or monthly, instead of one-off ordering.

## What it demonstrates (for your viva)

| DBMS concept | Where |
|---|---|
| Normalized schema (3NF) | `db/schema.sql` — 7 tables |
| Relationships | 1:1 (owner↔kitchen), 1:M (kitchen→weekly_menu, kitchen→plans, student→subscriptions), M:M in spirit (students subscribe to many kitchens' plans) |
| Triggers | `trg_validate_subscription_status` — blocks illegal status jumps (e.g. Cancelled → Active); `trg_auto_expire` — flips a subscription to Expired the moment its end_date passes |
| View | `kitchen_subscriber_summary` — active subscriber count + revenue per kitchen, powers the owner's dashboard |
| Stored procedures | `subscribe_student()` — creates a subscription + payment atomically, with the end date computed from the plan; `pause_subscription()` — extends `end_date` by N days and logs the pause |
| Transactions/ACID | Subscribing is one atomic operation — if anything fails, no partial subscription/payment is left behind |
| Two-sided CRUD | Kitchen owners manage their own menu/plans; students manage (pause/resume/cancel) their own subscriptions |
| Session persistence | Sessions are stored in Postgres via `connect-pg-simple` (auto-creates a `user_sessions` table), not in server memory — logins survive a server restart, which matters once this is deployed |
| Reviews + derived data | `reviews` table with a trigger (`trg_refresh_rating_insert`) that recalculates `kitchens.rating` as the live average whenever a review is added, edited, or deleted |
| Business model / commission | `kitchen_subscriber_summary` view now computes `platform_commission` and `net_payout` per kitchen from a per-kitchen `commission_percent` field |
| Platform-level admin | `platform_overview` view aggregates gross revenue, commission earned, verified kitchens, and reported reviews across the whole platform — a third role (`admin`) sits above students/kitchen owners |

## Two account types

- **Student** — browses kitchens, views weekly menus and plans, subscribes, can pause/resume/cancel.
- **Kitchen owner** — one kitchen per owner. Sets weekly menu (7 days × Lunch/Dinner), creates subscription plans, sees subscriber list and a revenue dashboard.

## Project structure

```
tiffin-trail-v2/
├── server.js
├── db/
│   ├── schema.sql       # tables, triggers, view, stored procedures, sample data
│   ├── seed.js
│   └── pool.js
├── middleware/auth.js
├── routes/               # auth.js, student.js, kitchen.js
├── views/
│   ├── kitchen/          # kitchen-owner-only pages
│   └── partials/
└── public/css/style.css
```

## Run it locally

```bash
npm install
cp .env.example .env      # then edit .env with your Postgres password AND your admin login
createdb tiffin_trail
node db/seed.js
npm start
```
Visit `http://localhost:3000`.

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

## Deploy (same as before)
See the deployment section pattern from v1 — Render + Render Postgres works the same way here. Just point `DATABASE_URL` at your new database and run `node db/seed.js` once from the Render shell.

## Good things to demo in your viva
- Subscribe to a plan → watch `subscribe_student()` create the subscription **and** the payment row in one call.
- Pause a subscription for a few days → the `end_date` visibly extends, showing the stored procedure at work.
- Try (via psql, for demonstration) updating a `Cancelled` subscription's status directly — the trigger will reject it.
- Kitchen owner dashboard — point out it's reading from a `VIEW`, not a raw table.
