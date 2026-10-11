-- Back2You: Lost Item Return & Ownership Management System
-- MySQL 8.0+   (run: mysql -u root -p < back2you_schema.sql)

DROP DATABASE IF EXISTS back2you;
CREATE DATABASE back2you CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE back2you;

-- ---------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------
CREATE TABLE users (
  user_id       INT AUTO_INCREMENT PRIMARY KEY,
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(150) NOT NULL UNIQUE,
  phone         VARCHAR(15),
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('user','staff','admin') NOT NULL DEFAULT 'user',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_email CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT chk_phone CHECK (phone IS NULL OR phone REGEXP '^[0-9+]{10,15}$')
);

CREATE TABLE categories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE locations (
  location_id INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(120) NOT NULL,
  type        ENUM('cab','bus','college','hostel','office','public') NOT NULL,
  city        VARCHAR(80) NOT NULL,
  UNIQUE (name, city)
);

CREATE TABLE items (
  item_id              INT AUTO_INCREMENT PRIMARY KEY,
  finder_id            INT NOT NULL,
  category_id          INT NOT NULL,
  location_id          INT NOT NULL,
  title                VARCHAR(120) NOT NULL,
  description          TEXT NOT NULL,
  color                VARCHAR(30),
  found_at             DATETIME NOT NULL,
  status               ENUM('registered','claimed','verified','handed_over','returned')
                       NOT NULL DEFAULT 'registered',
  current_custodian_id INT NOT NULL,          -- who physically holds it now
  vector_id            VARCHAR(64) NULL,      -- id of the embedding in Qdrant
  created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (finder_id)            REFERENCES users(user_id),
  FOREIGN KEY (category_id)          REFERENCES categories(category_id),
  FOREIGN KEY (location_id)          REFERENCES locations(location_id),
  FOREIGN KEY (current_custodian_id) REFERENCES users(user_id),
  CONSTRAINT chk_title_len CHECK (CHAR_LENGTH(TRIM(title)) >= 3),
  CONSTRAINT chk_desc_len  CHECK (CHAR_LENGTH(TRIM(description)) >= 10)
);

CREATE TABLE claims (
  claim_id         INT AUTO_INCREMENT PRIMARY KEY,
  item_id          INT NOT NULL,
  claimant_id      INT NOT NULL,
  description      TEXT NOT NULL,             -- claimant's description of lost item
  lost_at          DATETIME NOT NULL,
  lost_location_id INT NULL,
  status           ENUM('pending','verified','rejected','withdrawn') NOT NULL DEFAULT 'pending',
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id)          REFERENCES items(item_id),
  FOREIGN KEY (claimant_id)      REFERENCES users(user_id),
  FOREIGN KEY (lost_location_id) REFERENCES locations(location_id),
  UNIQUE (item_id, claimant_id),              -- one claim per person per item
  CONSTRAINT chk_claim_desc CHECK (CHAR_LENGTH(TRIM(description)) >= 10)
);

CREATE TABLE verification_attempts (
  attempt_id  INT AUTO_INCREMENT PRIMARY KEY,
  claim_id    INT NOT NULL,
  staff_id    INT NOT NULL,
  method      ENUM('secret_detail','photo_proof','id_document','purchase_proof') NOT NULL,
  notes       VARCHAR(255),
  result      ENUM('pass','fail') NOT NULL,
  attempted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (claim_id) REFERENCES claims(claim_id),
  FOREIGN KEY (staff_id) REFERENCES users(user_id)
);

CREATE TABLE custody_log (
  log_id       INT AUTO_INCREMENT PRIMARY KEY,
  item_id      INT NOT NULL,
  from_user_id INT NULL,                      -- NULL when first registered
  to_user_id   INT NOT NULL,
  note         VARCHAR(255),
  moved_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id)      REFERENCES items(item_id),
  FOREIGN KEY (from_user_id) REFERENCES users(user_id),
  FOREIGN KEY (to_user_id)   REFERENCES users(user_id)
);

CREATE TABLE handovers (
  handover_id INT AUTO_INCREMENT PRIMARY KEY,
  item_id     INT NOT NULL,
  claim_id    INT NOT NULL UNIQUE,            -- a claim can be handed over only once
  given_by    INT NOT NULL,
  received_by INT NOT NULL,
  handed_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  proof_type  ENUM('signature','photo','id_scan','otp') NOT NULL,
  proof_ref   VARCHAR(255) NOT NULL,
  FOREIGN KEY (item_id)     REFERENCES items(item_id),
  FOREIGN KEY (claim_id)    REFERENCES claims(claim_id),
  FOREIGN KEY (given_by)    REFERENCES users(user_id),
  FOREIGN KEY (received_by) REFERENCES users(user_id),
  CONSTRAINT chk_diff_parties CHECK (given_by <> received_by)
);

CREATE TABLE audit_log (
  audit_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
  table_name VARCHAR(40) NOT NULL,
  record_id  INT NOT NULL,
  action     ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  old_value  JSON NULL,
  new_value  JSON NULL,
  changed_by INT NULL,                        -- from @app_user_id set by the API
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------
-- 2. INDEXES (capture EXPLAIN before/after for your report)
-- ---------------------------------------------------------------
CREATE INDEX idx_items_status      ON items(status);
CREATE INDEX idx_items_cat_loc     ON items(category_id, location_id, found_at);
CREATE INDEX idx_claims_item_stat  ON claims(item_id, status);
CREATE INDEX idx_custody_item_time ON custody_log(item_id, moved_at);
CREATE INDEX idx_audit_table_rec   ON audit_log(table_name, record_id);
CREATE FULLTEXT INDEX ft_items_text ON items(title, description);

-- ---------------------------------------------------------------
-- 3. TRIGGERS
-- ---------------------------------------------------------------
DELIMITER $$

-- State machine: illegal status jumps are rejected by the database itself
CREATE TRIGGER trg_items_status_guard
BEFORE UPDATE ON items FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    IF NOT (
      (OLD.status = 'registered'  AND NEW.status = 'claimed')  OR
      (OLD.status = 'claimed'     AND NEW.status IN ('verified','registered')) OR
      (OLD.status = 'verified'    AND NEW.status IN ('handed_over','claimed')) OR
      (OLD.status = 'handed_over' AND NEW.status = 'returned')
    ) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Illegal item status transition';
    END IF;
  END IF;
END$$

-- First custody entry is written automatically when an item is registered
CREATE TRIGGER trg_items_first_custody
AFTER INSERT ON items FOR EACH ROW
BEGIN
  INSERT INTO custody_log (item_id, from_user_id, to_user_id, note)
  VALUES (NEW.item_id, NULL, NEW.current_custodian_id, 'Item registered');
  INSERT INTO audit_log (table_name, record_id, action, new_value, changed_by)
  VALUES ('items', NEW.item_id, 'INSERT',
          JSON_OBJECT('status', NEW.status, 'title', NEW.title), @app_user_id);
END$$

-- Audit trail of item changes
CREATE TRIGGER trg_items_audit
AFTER UPDATE ON items FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
  VALUES ('items', NEW.item_id, 'UPDATE',
          JSON_OBJECT('status', OLD.status, 'custodian', OLD.current_custodian_id),
          JSON_OBJECT('status', NEW.status, 'custodian', NEW.current_custodian_id),
          @app_user_id);
END$$

-- A new claim moves a registered item to 'claimed'
CREATE TRIGGER trg_claim_marks_item
AFTER INSERT ON claims FOR EACH ROW
BEGIN
  UPDATE items SET status = 'claimed'
  WHERE item_id = NEW.item_id AND status = 'registered';
END$$

-- ---------------------------------------------------------------
-- 4. STORED PROCEDURE: atomic handover (transaction + row locks)
-- ---------------------------------------------------------------
CREATE PROCEDURE perform_handover(
  IN p_claim_id   INT,
  IN p_staff_id   INT,
  IN p_proof_type VARCHAR(20),
  IN p_proof_ref  VARCHAR(255)
)
BEGIN
  DECLARE v_item_id INT;
  DECLARE v_claimant INT;
  DECLARE v_claim_status VARCHAR(20);
  DECLARE v_item_status VARCHAR(20);
  DECLARE v_custodian INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT item_id, claimant_id, status
    INTO v_item_id, v_claimant, v_claim_status
    FROM claims WHERE claim_id = p_claim_id FOR UPDATE;

  SELECT status, current_custodian_id
    INTO v_item_status, v_custodian
    FROM items WHERE item_id = v_item_id FOR UPDATE;

  IF v_claim_status <> 'verified' OR v_item_status <> 'verified' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Claim must be verified before handover';
  END IF;

  INSERT INTO handovers (item_id, claim_id, given_by, received_by, proof_type, proof_ref)
  VALUES (v_item_id, p_claim_id, p_staff_id, v_claimant, p_proof_type, p_proof_ref);

  INSERT INTO custody_log (item_id, from_user_id, to_user_id, note)
  VALUES (v_item_id, v_custodian, v_claimant, 'Handed over to verified owner');

  SET @app_user_id = p_staff_id;
  UPDATE items SET status = 'handed_over', current_custodian_id = v_claimant
  WHERE item_id = v_item_id;

  COMMIT;
END$$

DELIMITER ;

-- ---------------------------------------------------------------
-- 5. VIEWS
-- ---------------------------------------------------------------
CREATE VIEW v_item_timeline AS
SELECT c.item_id, i.title, c.moved_at,
       fu.full_name AS from_person, tu.full_name AS to_person, c.note
FROM custody_log c
JOIN items i  ON i.item_id = c.item_id
LEFT JOIN users fu ON fu.user_id = c.from_user_id
JOIN users tu ON tu.user_id = c.to_user_id;

CREATE VIEW v_unclaimed_items AS
SELECT i.item_id, i.title, cat.name AS category, l.name AS location,
       DATEDIFF(NOW(), i.found_at) AS days_waiting
FROM items i
JOIN categories cat ON cat.category_id = i.category_id
JOIN locations l    ON l.location_id = i.location_id
WHERE i.status = 'registered';

CREATE VIEW v_admin_dashboard AS
SELECT l.type AS location_type,
       COUNT(*) AS total_items,
       SUM(i.status = 'returned') AS returned_items,
       ROUND(100 * SUM(i.status = 'returned') / COUNT(*), 1) AS return_rate_pct
FROM items i JOIN locations l ON l.location_id = i.location_id
GROUP BY l.type;

-- ---------------------------------------------------------------
-- 6. MIGRATION EXAMPLE (rubric lists ALTER and DROP)
-- ---------------------------------------------------------------
-- ALTER TABLE items ADD COLUMN brand VARCHAR(50) NULL AFTER color;
-- ALTER TABLE items DROP COLUMN brand;
-- DROP VIEW IF EXISTS v_unclaimed_items;
