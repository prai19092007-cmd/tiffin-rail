-- ============================================
-- TiffinRail v2 — Tiffin/Mess Subscription Marketplace
-- PostgreSQL
-- ============================================

DROP TABLE IF EXISTS favorites CASCADE;
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS subscription_pauses CASCADE;
DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS subscription_plans CASCADE;
DROP TABLE IF EXISTS weekly_menu CASCADE;
DROP TABLE IF EXISTS kitchens CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- ============================================
-- TABLES
-- ============================================

CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(150) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone         VARCHAR(20),
    address       VARCHAR(255),
    role          VARCHAR(20) NOT NULL CHECK (role IN ('student', 'kitchen_owner', 'admin')),
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE kitchens (
    kitchen_id    SERIAL PRIMARY KEY,
    owner_id      INTEGER NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    name          VARCHAR(150) NOT NULL,
    cuisine_type  VARCHAR(100),
    location      VARCHAR(255),
    description   VARCHAR(500),
    food_type     VARCHAR(10) NOT NULL DEFAULT 'Veg' CHECK (food_type IN ('Veg','Non-Veg','Both')),
    image_url     VARCHAR(500),
    is_verified   BOOLEAN NOT NULL DEFAULT FALSE,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected')),
    commission_percent NUMERIC(4,1) NOT NULL DEFAULT 10.0 CHECK (commission_percent >= 0 AND commission_percent <= 100),
    rating        NUMERIC(2,1) DEFAULT 0.0 CHECK (rating >= 0 AND rating <= 5),
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE weekly_menu (
    menu_id       SERIAL PRIMARY KEY,
    kitchen_id    INTEGER NOT NULL REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    day_of_week   VARCHAR(10) NOT NULL CHECK (day_of_week IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
    meal_type     VARCHAR(10) NOT NULL CHECK (meal_type IN ('Lunch','Dinner')),
    description   VARCHAR(300) NOT NULL,
    UNIQUE (kitchen_id, day_of_week, meal_type)
);

CREATE TABLE subscription_plans (
    plan_id       SERIAL PRIMARY KEY,
    kitchen_id    INTEGER NOT NULL REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    name          VARCHAR(100) NOT NULL,
    duration_days INTEGER NOT NULL CHECK (duration_days IN (7, 30)),
    meals_per_day INTEGER NOT NULL DEFAULT 1 CHECK (meals_per_day IN (1, 2)),
    price         NUMERIC(8,2) NOT NULL CHECK (price > 0),
    active        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE subscriptions (
    subscription_id SERIAL PRIMARY KEY,
    student_id      INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    kitchen_id      INTEGER NOT NULL REFERENCES kitchens(kitchen_id),
    plan_id         INTEGER NOT NULL REFERENCES subscription_plans(plan_id),
    start_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date        DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'Active'
                    CHECK (status IN ('Active','Paused','Expired','Cancelled')),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE subscription_pauses (
    pause_id        SERIAL PRIMARY KEY,
    subscription_id INTEGER NOT NULL REFERENCES subscriptions(subscription_id) ON DELETE CASCADE,
    pause_days      INTEGER NOT NULL CHECK (pause_days > 0),
    reason          VARCHAR(255),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE payments (
    payment_id      SERIAL PRIMARY KEY,
    subscription_id INTEGER NOT NULL REFERENCES subscriptions(subscription_id) ON DELETE CASCADE,
    amount          NUMERIC(10,2) NOT NULL,
    method          VARCHAR(20) NOT NULL DEFAULT 'UPI' CHECK (method IN ('UPI','Card','Cash')),
    status          VARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending','Paid','Failed')),
    paid_at         TIMESTAMP
);

CREATE TABLE favorites (
    favorite_id   SERIAL PRIMARY KEY,
    student_id    INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    kitchen_id    INTEGER NOT NULL REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (student_id, kitchen_id)
);

CREATE TABLE reviews (
    review_id     SERIAL PRIMARY KEY,
    kitchen_id    INTEGER NOT NULL REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    student_id    INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    rating        INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment       VARCHAR(500),
    reported      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (kitchen_id, student_id)
);

-- ============================================
-- TRIGGER 0: Keep kitchens.rating in sync with the average of its reviews
-- ============================================
CREATE OR REPLACE FUNCTION refresh_kitchen_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_kitchen_id INTEGER := COALESCE(NEW.kitchen_id, OLD.kitchen_id);
BEGIN
    UPDATE kitchens
    SET rating = COALESCE((SELECT ROUND(AVG(rating), 1) FROM reviews WHERE kitchen_id = v_kitchen_id), 0)
    WHERE kitchen_id = v_kitchen_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_rating_insert
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW EXECUTE FUNCTION refresh_kitchen_rating();

-- ============================================
-- TRIGGER 1: Validate subscription status transitions
-- ============================================
CREATE OR REPLACE FUNCTION validate_subscription_status()
RETURNS TRIGGER AS $$
DECLARE
    valid_next VARCHAR[];
BEGIN
    IF OLD.status IN ('Cancelled', 'Expired') THEN
        RAISE EXCEPTION 'Cannot change status of a subscription that is already %', OLD.status;
    END IF;

    valid_next := CASE OLD.status
        WHEN 'Active' THEN ARRAY['Paused','Cancelled','Expired']
        WHEN 'Paused' THEN ARRAY['Active','Cancelled','Expired']
        ELSE ARRAY[]::VARCHAR[]
    END;

    IF NEW.status <> OLD.status AND NOT (NEW.status = ANY(valid_next)) THEN
        RAISE EXCEPTION 'Invalid status transition from % to %', OLD.status, NEW.status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_subscription_status
BEFORE UPDATE OF status ON subscriptions
FOR EACH ROW EXECUTE FUNCTION validate_subscription_status();

-- ============================================
-- TRIGGER 2: Auto-expire subscriptions whose end_date has passed
-- (runs opportunistically whenever a subscription row is touched;
--  paired with an app-level check on every page load)
-- ============================================
CREATE OR REPLACE FUNCTION auto_expire_subscription()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.end_date < CURRENT_DATE AND NEW.status = 'Active' THEN
        NEW.status := 'Expired';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_expire
BEFORE UPDATE ON subscriptions
FOR EACH ROW EXECUTE FUNCTION auto_expire_subscription();

-- ============================================
-- VIEW: Kitchen subscriber & revenue summary
-- ============================================
CREATE OR REPLACE VIEW kitchen_subscriber_summary AS
SELECT
    k.kitchen_id,
    k.name AS kitchen_name,
    k.commission_percent,
    COUNT(s.subscription_id) AS total_subscriptions,
    COUNT(s.subscription_id) FILTER (WHERE s.status = 'Active') AS active_subscribers,
    COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'Paid'), 0) AS total_revenue,
    ROUND(COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'Paid'), 0) * k.commission_percent / 100, 2) AS platform_commission,
    ROUND(COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'Paid'), 0) * (1 - k.commission_percent / 100), 2) AS net_payout
FROM kitchens k
LEFT JOIN subscriptions s ON s.kitchen_id = k.kitchen_id
LEFT JOIN payments p ON p.subscription_id = s.subscription_id
GROUP BY k.kitchen_id, k.name, k.commission_percent;

-- ============================================
-- VIEW: Platform-wide overview (for the admin dashboard)
-- ============================================
CREATE OR REPLACE VIEW platform_overview AS
SELECT
    (SELECT COUNT(*) FROM kitchens) AS total_kitchens,
    (SELECT COUNT(*) FROM kitchens WHERE is_verified = TRUE) AS verified_kitchens,
    (SELECT COUNT(*) FROM kitchens WHERE approval_status = 'pending') AS pending_kitchens,
    (SELECT COUNT(*) FROM users WHERE role = 'student') AS total_students,
    (SELECT COUNT(*) FROM subscriptions WHERE status = 'Active') AS active_subscriptions,
    (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'Paid') AS platform_gross_revenue,
    (SELECT COALESCE(SUM(p.amount * k.commission_percent / 100), 0)
       FROM payments p JOIN subscriptions s ON s.subscription_id = p.subscription_id
       JOIN kitchens k ON k.kitchen_id = s.kitchen_id
       WHERE p.status = 'Paid') AS platform_commission_earned,
    (SELECT COUNT(*) FROM reviews WHERE reported = TRUE) AS reported_reviews;

-- ============================================
-- STORED PROCEDURE: Subscribe a student to a plan (atomic)
-- ============================================
CREATE OR REPLACE FUNCTION subscribe_student(
    p_student_id INTEGER,
    p_plan_id INTEGER
) RETURNS INTEGER AS $$
DECLARE
    v_kitchen_id INTEGER;
    v_duration INTEGER;
    v_price NUMERIC(8,2);
    v_subscription_id INTEGER;
BEGIN
    SELECT kitchen_id, duration_days, price INTO v_kitchen_id, v_duration, v_price
    FROM subscription_plans WHERE plan_id = p_plan_id AND active = TRUE;

    IF v_kitchen_id IS NULL THEN
        RAISE EXCEPTION 'Plan % is not available', p_plan_id;
    END IF;

    INSERT INTO subscriptions (student_id, kitchen_id, plan_id, start_date, end_date, status)
    VALUES (p_student_id, v_kitchen_id, p_plan_id, CURRENT_DATE, CURRENT_DATE + v_duration, 'Active')
    RETURNING subscription_id INTO v_subscription_id;

    INSERT INTO payments (subscription_id, amount, method, status, paid_at)
    VALUES (v_subscription_id, v_price, 'UPI', 'Paid', NOW());

    RETURN v_subscription_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- STORED PROCEDURE: Pause a subscription (extends end_date)
-- ============================================
CREATE OR REPLACE FUNCTION pause_subscription(
    p_subscription_id INTEGER,
    p_days INTEGER,
    p_reason VARCHAR
) RETURNS VOID AS $$
BEGIN
    UPDATE subscriptions
    SET end_date = end_date + p_days,
        status = 'Paused'
    WHERE subscription_id = p_subscription_id AND status = 'Active';

    INSERT INTO subscription_pauses (subscription_id, pause_days, reason)
    VALUES (p_subscription_id, p_days, p_reason);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- SAMPLE DATA
-- ============================================

-- Kitchen owners
INSERT INTO users (name, email, password_hash, phone, address, role) VALUES
('Sunita Sharma', 'sunita@ghar.com', '$2b$10$placeholder', '9000000001', 'Sector 12', 'kitchen_owner'),
('Ramesh Yadav', 'ramesh@tiffin.com', '$2b$10$placeholder', '9000000002', 'Station Road', 'kitchen_owner');

INSERT INTO kitchens (owner_id, name, cuisine_type, location, description, food_type, image_url, rating) VALUES
(1, 'Ghar Ka Khana', 'North Indian Home-style', 'Sector 12, Kushinagar', 'Homemade thalis, just like maa ke haath ka khana.', 'Veg', 'https://commons.wikimedia.org/wiki/Special:FilePath/Traditional_North_Indian_Thali.jpg?width=600', 4.6),
(2, 'Ramesh Tiffin Service', 'North Indian', 'Station Road, near campus gate', 'Affordable daily tiffin for students, hygienic and on-time.', 'Both', 'https://commons.wikimedia.org/wiki/Special:FilePath/Tiffin_wallah_lunch.jpg?width=600', 4.2);

INSERT INTO weekly_menu (kitchen_id, day_of_week, meal_type, description) VALUES
(1, 'Monday', 'Lunch', 'Dal, Rice, Aloo Sabzi, Roti, Salad'),
(1, 'Monday', 'Dinner', 'Rajma, Rice, Roti'),
(1, 'Tuesday', 'Lunch', 'Chole, Rice, Roti, Salad'),
(1, 'Tuesday', 'Dinner', 'Mix Veg, Roti, Dal'),
(2, 'Monday', 'Lunch', 'Dal Fry, Rice, Bhindi, Roti'),
(2, 'Monday', 'Dinner', 'Paneer Bhurji, Roti, Dal'),
(2, 'Tuesday', 'Lunch', 'Kadhi, Rice, Roti, Papad');

INSERT INTO subscription_plans (kitchen_id, name, duration_days, meals_per_day, price) VALUES
(1, 'Weekly Lunch Only', 7, 1, 490),
(1, 'Monthly Lunch + Dinner', 30, 2, 3200),
(2, 'Weekly Full Tiffin', 7, 2, 700),
(2, 'Monthly Lunch Only', 30, 1, 2100);

-- Sample students + reviews so the reviews section has content to demo
INSERT INTO users (name, email, password_hash, phone, address, role) VALUES
('Aman Verma', 'aman@student.com', '$2b$10$placeholder', '9111111111', 'Hostel Block A', 'student'),
('Priya Singh', 'priya@student.com', '$2b$10$placeholder', '9222222222', 'Hostel Block B', 'student');

INSERT INTO reviews (kitchen_id, student_id, rating, comment) VALUES
(1, 3, 5, 'Tastes just like home food. Portion size is generous too.'),
(1, 4, 4, 'Good food overall, sometimes a bit late on Sundays.'),
(2, 3, 4, 'Reliable and on time every day. Roti could be softer.');

-- Platform admin account
INSERT INTO users (name, email, password_hash, phone, address, role) VALUES
('Platform Admin', 'admin@tiffinexpress.com', '$2b$10$placeholder', '9999999999', 'HQ', 'admin');

-- Mark one kitchen as verified for demo purposes
UPDATE kitchens SET is_verified = TRUE WHERE kitchen_id = 1;

-- Demo kitchens are pre-approved so the platform has visible content out of the box
UPDATE kitchens SET approval_status = 'approved' WHERE kitchen_id IN (1, 2);
