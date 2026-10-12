-- ============================================
-- TiffinRail — Tiffin/Mess Subscription Marketplace
-- MySQL 8.0 (InnoDB)
--
-- Create an empty database first, then run this file against it:
--   CREATE DATABASE tiffin_rail CHARACTER SET utf8mb4;
--   mysql -u root -p tiffin_rail < db/schema.sql      (or run `node db/seed.js`)
-- ============================================

SET NAMES utf8mb4;

DROP VIEW IF EXISTS platform_overview;
DROP VIEW IF EXISTS kitchen_subscriber_summary;
DROP PROCEDURE IF EXISTS subscribe_student;
DROP PROCEDURE IF EXISTS pause_subscription;

-- Child tables first, so foreign keys never block a DROP
DROP TABLE IF EXISTS favorites;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS subscription_pauses;
DROP TABLE IF EXISTS subscriptions;
DROP TABLE IF EXISTS subscription_plans;
DROP TABLE IF EXISTS weekly_menu;
DROP TABLE IF EXISTS kitchens;
DROP TABLE IF EXISTS users;

-- ============================================
-- TABLES
-- ============================================

CREATE TABLE users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone         VARCHAR(20),
    address       VARCHAR(255),
    role          VARCHAR(20) NOT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_users_role CHECK (role IN ('student', 'kitchen_owner', 'admin'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE kitchens (
    kitchen_id    INT AUTO_INCREMENT PRIMARY KEY,
    owner_id      INT NOT NULL UNIQUE,
    name          VARCHAR(150) NOT NULL,
    cuisine_type  VARCHAR(100),
    location      VARCHAR(255),
    description   VARCHAR(500),
    food_type     VARCHAR(10) NOT NULL DEFAULT 'Veg',
    image_url     VARCHAR(500),
    is_verified   BOOLEAN NOT NULL DEFAULT FALSE,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    commission_percent DECIMAL(4,1) NOT NULL DEFAULT 10.0,
    rating        DECIMAL(2,1) DEFAULT 0.0,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_kitchens_owner FOREIGN KEY (owner_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_kitchens_food_type CHECK (food_type IN ('Veg','Non-Veg','Both')),
    CONSTRAINT chk_kitchens_approval CHECK (approval_status IN ('pending','approved','rejected')),
    CONSTRAINT chk_kitchens_commission CHECK (commission_percent >= 0 AND commission_percent <= 100),
    CONSTRAINT chk_kitchens_rating CHECK (rating >= 0 AND rating <= 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE weekly_menu (
    menu_id       INT AUTO_INCREMENT PRIMARY KEY,
    kitchen_id    INT NOT NULL,
    day_of_week   VARCHAR(10) NOT NULL,
    meal_type     VARCHAR(10) NOT NULL,
    description   VARCHAR(300) NOT NULL,
    CONSTRAINT fk_menu_kitchen FOREIGN KEY (kitchen_id) REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    CONSTRAINT uq_menu_slot UNIQUE (kitchen_id, day_of_week, meal_type),
    CONSTRAINT chk_menu_day CHECK (day_of_week IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
    CONSTRAINT chk_menu_meal CHECK (meal_type IN ('Lunch','Dinner'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE subscription_plans (
    plan_id       INT AUTO_INCREMENT PRIMARY KEY,
    kitchen_id    INT NOT NULL,
    name          VARCHAR(100) NOT NULL,
    duration_days INT NOT NULL,
    meals_per_day INT NOT NULL DEFAULT 1,
    price         DECIMAL(8,2) NOT NULL,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_plans_kitchen FOREIGN KEY (kitchen_id) REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    CONSTRAINT chk_plans_duration CHECK (duration_days IN (7, 30)),
    CONSTRAINT chk_plans_meals CHECK (meals_per_day IN (1, 2)),
    CONSTRAINT chk_plans_price CHECK (price > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE subscriptions (
    subscription_id INT AUTO_INCREMENT PRIMARY KEY,
    student_id      INT NOT NULL,
    kitchen_id      INT NOT NULL,
    plan_id         INT NOT NULL,
    start_date      DATE NOT NULL DEFAULT (CURRENT_DATE),
    end_date        DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'Active',
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_subs_student FOREIGN KEY (student_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_subs_kitchen FOREIGN KEY (kitchen_id) REFERENCES kitchens(kitchen_id),
    CONSTRAINT fk_subs_plan FOREIGN KEY (plan_id) REFERENCES subscription_plans(plan_id),
    CONSTRAINT chk_subs_status CHECK (status IN ('Active','Paused','Expired','Cancelled'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE subscription_pauses (
    pause_id        INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id INT NOT NULL,
    pause_days      INT NOT NULL,
    reason          VARCHAR(255),
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pauses_sub FOREIGN KEY (subscription_id) REFERENCES subscriptions(subscription_id) ON DELETE CASCADE,
    CONSTRAINT chk_pauses_days CHECK (pause_days > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE payments (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id INT NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    method          VARCHAR(20) NOT NULL DEFAULT 'UPI',
    status          VARCHAR(20) NOT NULL DEFAULT 'Pending',
    paid_at         DATETIME NULL,
    CONSTRAINT fk_payments_sub FOREIGN KEY (subscription_id) REFERENCES subscriptions(subscription_id) ON DELETE CASCADE,
    CONSTRAINT chk_payments_method CHECK (method IN ('UPI','Card','Cash')),
    CONSTRAINT chk_payments_status CHECK (status IN ('Pending','Paid','Failed'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE favorites (
    favorite_id   INT AUTO_INCREMENT PRIMARY KEY,
    student_id    INT NOT NULL,
    kitchen_id    INT NOT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fav_student FOREIGN KEY (student_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_fav_kitchen FOREIGN KEY (kitchen_id) REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    CONSTRAINT uq_fav_pair UNIQUE (student_id, kitchen_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE reviews (
    review_id     INT AUTO_INCREMENT PRIMARY KEY,
    kitchen_id    INT NOT NULL,
    student_id    INT NOT NULL,
    rating        INT NOT NULL,
    comment       VARCHAR(500),
    reported      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reviews_kitchen FOREIGN KEY (kitchen_id) REFERENCES kitchens(kitchen_id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_student FOREIGN KEY (student_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT uq_review_pair UNIQUE (kitchen_id, student_id),
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- TRIGGERS, PROCEDURES (need a custom delimiter because their bodies contain ';')
-- ============================================
DELIMITER $$

-- --------------------------------------------
-- TRIGGER 0: Keep kitchens.rating in sync with the average of its reviews.
-- MySQL has no "AFTER INSERT OR UPDATE OR DELETE" — one trigger per event.
-- --------------------------------------------
CREATE TRIGGER trg_refresh_rating_insert
AFTER INSERT ON reviews
FOR EACH ROW
BEGIN
    UPDATE kitchens
    SET rating = COALESCE((SELECT ROUND(AVG(reviews.rating), 1) FROM reviews WHERE reviews.kitchen_id = NEW.kitchen_id), 0)
    WHERE kitchen_id = NEW.kitchen_id;
END$$

CREATE TRIGGER trg_refresh_rating_update
AFTER UPDATE ON reviews
FOR EACH ROW
BEGIN
    UPDATE kitchens
    SET rating = COALESCE((SELECT ROUND(AVG(reviews.rating), 1) FROM reviews WHERE reviews.kitchen_id = NEW.kitchen_id), 0)
    WHERE kitchen_id = NEW.kitchen_id;
END$$

CREATE TRIGGER trg_refresh_rating_delete
AFTER DELETE ON reviews
FOR EACH ROW
BEGIN
    UPDATE kitchens
    SET rating = COALESCE((SELECT ROUND(AVG(reviews.rating), 1) FROM reviews WHERE reviews.kitchen_id = OLD.kitchen_id), 0)
    WHERE kitchen_id = OLD.kitchen_id;
END$$

-- --------------------------------------------
-- TRIGGER 2: Auto-expire subscriptions whose end_date has passed
-- (runs whenever a subscription row is updated; paired with an
--  app-level check on the My Subscriptions page)
-- --------------------------------------------
CREATE TRIGGER trg_auto_expire
BEFORE UPDATE ON subscriptions
FOR EACH ROW
BEGIN
    IF NEW.end_date < CURRENT_DATE AND NEW.status = 'Active' THEN
        SET NEW.status = 'Expired';
    END IF;
END$$

-- --------------------------------------------
-- TRIGGER 1: Validate subscription status transitions.
-- FOLLOWS trg_auto_expire so it checks the status *after* auto-expiry,
-- exactly like the original design.
-- --------------------------------------------
CREATE TRIGGER trg_validate_subscription_status
BEFORE UPDATE ON subscriptions
FOR EACH ROW
FOLLOWS trg_auto_expire
BEGIN
    IF NEW.status <> OLD.status THEN
        IF OLD.status IN ('Cancelled', 'Expired') THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Cannot change status of a subscription that is already Cancelled or Expired';
        END IF;

        IF NOT (
            (OLD.status = 'Active' AND NEW.status IN ('Paused', 'Cancelled', 'Expired')) OR
            (OLD.status = 'Paused' AND NEW.status IN ('Active', 'Cancelled', 'Expired'))
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Invalid subscription status transition';
        END IF;
    END IF;
END$$

-- --------------------------------------------
-- STORED PROCEDURE: Subscribe a student to a plan (atomic).
-- Creates the subscription AND its payment in one transaction;
-- any failure rolls both back. Returns the new subscription_id.
-- --------------------------------------------
CREATE PROCEDURE subscribe_student(
    IN p_student_id INT,
    IN p_plan_id INT
)
BEGIN
    DECLARE v_kitchen_id INT DEFAULT NULL;
    DECLARE v_duration INT;
    DECLARE v_price DECIMAL(8,2);
    DECLARE v_subscription_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT kitchen_id, duration_days, price
    INTO v_kitchen_id, v_duration, v_price
    FROM subscription_plans
    WHERE plan_id = p_plan_id AND active = TRUE;

    IF v_kitchen_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Plan is not available';
    END IF;

    INSERT INTO subscriptions (student_id, kitchen_id, plan_id, start_date, end_date, status)
    VALUES (p_student_id, v_kitchen_id, p_plan_id, CURRENT_DATE, DATE_ADD(CURRENT_DATE, INTERVAL v_duration DAY), 'Active');

    SET v_subscription_id = LAST_INSERT_ID();

    INSERT INTO payments (subscription_id, amount, method, status, paid_at)
    VALUES (v_subscription_id, v_price, 'UPI', 'Paid', NOW());

    COMMIT;

    SELECT v_subscription_id AS subscription_id;
END$$

-- --------------------------------------------
-- STORED PROCEDURE: Pause a subscription (extends end_date by N days
-- and logs the pause). Only an Active subscription can be paused.
-- --------------------------------------------
CREATE PROCEDURE pause_subscription(
    IN p_subscription_id INT,
    IN p_days INT,
    IN p_reason VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE subscriptions
    SET end_date = DATE_ADD(end_date, INTERVAL p_days DAY),
        status = 'Paused'
    WHERE subscription_id = p_subscription_id AND status = 'Active';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an Active subscription can be paused';
    END IF;

    INSERT INTO subscription_pauses (subscription_id, pause_days, reason)
    VALUES (p_subscription_id, p_days, p_reason);

    COMMIT;
END$$

DELIMITER ;

-- ============================================
-- VIEW: Kitchen subscriber & revenue summary
-- ============================================
CREATE OR REPLACE VIEW kitchen_subscriber_summary AS
SELECT
    k.kitchen_id,
    k.name AS kitchen_name,
    k.commission_percent,
    COUNT(s.subscription_id) AS total_subscriptions,
    COUNT(CASE WHEN s.status = 'Active' THEN s.subscription_id END) AS active_subscribers,
    COALESCE(SUM(CASE WHEN p.status = 'Paid' THEN p.amount END), 0) AS total_revenue,
    ROUND(COALESCE(SUM(CASE WHEN p.status = 'Paid' THEN p.amount END), 0) * k.commission_percent / 100, 2) AS platform_commission,
    ROUND(COALESCE(SUM(CASE WHEN p.status = 'Paid' THEN p.amount END), 0) * (1 - k.commission_percent / 100), 2) AS net_payout
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
    (SELECT ROUND(COALESCE(SUM(p.amount * k.commission_percent / 100), 0), 2)
       FROM payments p JOIN subscriptions s ON s.subscription_id = p.subscription_id
       JOIN kitchens k ON k.kitchen_id = s.kitchen_id
       WHERE p.status = 'Paid') AS platform_commission_earned,
    (SELECT COUNT(*) FROM reviews WHERE reported = TRUE) AS reported_reviews;

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
