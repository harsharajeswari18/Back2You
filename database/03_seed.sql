-- Back2You: seed data (run on a FRESH database: schema -> procedures -> seed)
-- Items get item_id 1..300 in order, and the script relies on that.
--
-- Ground truth for match-quality testing:
--   claims on items 1..150 point at the item they truly describe (claims.item_id),
--   so each of those claims is a lost/found pair. Reword some of the claim texts
--   by hand (different words than the item text) for a more honest accuracy number.
USE back2you;
SET @app_user_id = 3;          -- audit rows get a changed_by

-- ---------------- users: 2 admins, 8 staff, 50 normal users ----------------
INSERT INTO users (full_name, email, phone, password_hash, role)
WITH RECURSIVE seq (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 60
)
SELECT
  CONCAT(ELT(1 + n % 10, 'Aarav','Diya','Vihaan','Ananya','Rohan','Meera','Karthik','Sneha','Arjun','Priya'),
         ' ', ELT(1 + (n DIV 10) % 6, 'Sharma','Reddy','Iyer','Nair','Gupta','Rao')),
  CONCAT('user', n, '@back2you.test'),
  CONCAT('9', LPAD(n, 9, '0')),
  'CHANGE_ME_BCRYPT_HASH',
  CASE WHEN n <= 2 THEN 'admin' WHEN n <= 10 THEN 'staff' ELSE 'user' END
FROM seq;

-- ---------------- categories (order matters: matches noun list below) -------
INSERT INTO categories (name) VALUES
 ('Phone'),('Wallet'),('Keys'),('Laptop'),('Bag'),
 ('Earphones'),('ID Card'),('Watch'),('Umbrella'),('Water Bottle');

-- ---------------- locations ----------------
INSERT INTO locations (name, type, city) VALUES
 ('Cab KA01-1234','cab','Bengaluru'),('Cab KA03-5678','cab','Bengaluru'),
 ('Cab KA05-9012','cab','Bengaluru'),
 ('BMTC Route 500D','bus','Bengaluru'),('BMTC Route 335E','bus','Bengaluru'),
 ('BMTC Route 201','bus','Bengaluru'),
 ('PES Main Block','college','Bengaluru'),('PES Library','college','Bengaluru'),
 ('PES Canteen','college','Bengaluru'),
 ('Boys Hostel A','hostel','Bengaluru'),('Girls Hostel B','hostel','Bengaluru'),
 ('Tech Park Tower 1','office','Bengaluru'),('Tech Park Tower 2','office','Bengaluru'),
 ('Indiranagar Co-working','office','Bengaluru'),
 ('Cubbon Park','public','Bengaluru'),('MG Road Metro','public','Bengaluru'),
 ('Majestic Bus Stand','public','Bengaluru'),('Lalbagh Gate','public','Bengaluru'),
 ('Phoenix Mall','public','Bengaluru'),('Koramangala Cafe','public','Bengaluru');

-- ---------------- 300 found items (triggers add custody + audit rows) -------
INSERT INTO items (finder_id, category_id, location_id, title, description,
                   color, found_at, current_custodian_id)
WITH RECURSIVE seq (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 300
),
base AS (
  SELECT n,
    1 + n % 10        AS cat,
    1 + (n * 7) % 20  AS loc,
    ELT(1 + n % 8, 'black','blue','red','silver','white','green','brown','grey') AS color,
    ELT(1 + n % 10, 'smartphone','leather wallet','bunch of keys','laptop','backpack',
        'wireless earbuds','student ID card','wrist watch','folding umbrella',
        'steel water bottle') AS noun,
    ELT(1 + (n DIV 10) % 6, 'with a small scratch','with a sticker on it',
        'with a blue keychain attached','inside a black pouch',
        'with initials engraved','that looks slightly worn') AS feat
  FROM seq
)
SELECT 11 + n % 50, cat, loc,
       CONCAT(color, ' ', noun),
       CONCAT('Found a ', color, ' ', noun, ' ', feat, ' near ',
              (SELECT name FROM locations WHERE location_id = loc), '.'),
       color,
       NOW() - INTERVAL (n % 60) DAY - INTERVAL ((n * 37) % 1440) MINUTE,
       3 + n % 8
FROM base;

-- Staging copy: a trigger on claims updates items, so we cannot read items
-- directly in the same INSERT (MySQL error 1442).
CREATE TEMPORARY TABLE seed_items AS
SELECT i.item_id, i.title, i.found_at, i.location_id, l.name AS loc_name
FROM items i JOIN locations l ON l.location_id = i.location_id;

-- ---------------- claims on items 1..150 (true owner of each item) ----------
INSERT INTO claims (item_id, claimant_id, description, lost_at, lost_location_id)
SELECT s.item_id, 11 + (s.item_id + 17) % 50,
       CONCAT('I lost my ', s.title, ' around ', s.loc_name, '. ',
              ELT(1 + s.item_id % 4, 'It is a bit worn.', 'It has a few stickers on it.',
                  'I kept it in a small pouch.', 'There are my initials on it.')),
       s.found_at - INTERVAL 5 HOUR, s.location_id
FROM seed_items s WHERE s.item_id <= 150;

-- competing second claims on items 1..20 (someone else says it is theirs)
INSERT INTO claims (item_id, claimant_id, description, lost_at, lost_location_id)
SELECT s.item_id, 11 + (s.item_id + 31) % 50,
       CONCAT('I think the ', s.title, ' found at ', s.loc_name, ' belongs to me.'),
       s.found_at - INTERVAL 8 HOUR, s.location_id
FROM seed_items s WHERE s.item_id <= 20;

-- ---------------- verification outcomes ----------------
-- items 41..100: verification passes
INSERT INTO verification_attempts (claim_id, staff_id, method, notes, result)
SELECT c.claim_id, 3 + c.item_id % 8,
       ELT(1 + c.item_id % 4, 'secret_detail','photo_proof','id_document','purchase_proof'),
       'Owner provided matching details', 'pass'
FROM claims c WHERE c.item_id BETWEEN 41 AND 100;

-- items 101..130: verification fails
INSERT INTO verification_attempts (claim_id, staff_id, method, notes, result)
SELECT c.claim_id, 3 + c.item_id % 8,
       ELT(1 + c.item_id % 4, 'secret_detail','photo_proof','id_document','purchase_proof'),
       'Details did not match the item', 'fail'
FROM claims c WHERE c.item_id BETWEEN 101 AND 130;

UPDATE claims SET status = 'verified' WHERE item_id BETWEEN 41 AND 100;
UPDATE claims SET status = 'rejected' WHERE item_id BETWEEN 101 AND 130;
UPDATE items  SET status = 'verified'   WHERE item_id BETWEEN 41 AND 100;   -- claimed -> verified
UPDATE items  SET status = 'registered' WHERE item_id BETWEEN 101 AND 130;  -- claimed -> registered

-- ---------------- handovers for items 41..70 ----------------
INSERT INTO handovers (item_id, claim_id, given_by, received_by, handed_at, proof_type, proof_ref)
SELECT c.item_id, c.claim_id, i.current_custodian_id, c.claimant_id,
       LEAST(NOW(), i.found_at + INTERVAL 3 DAY),
       ELT(1 + c.item_id % 4, 'signature','photo','id_scan','otp'),
       CONCAT('proof_', c.claim_id)
FROM claims c JOIN items i ON i.item_id = c.item_id
WHERE c.item_id BETWEEN 41 AND 70 AND c.status = 'verified';

INSERT INTO custody_log (item_id, from_user_id, to_user_id, note, moved_at)
SELECT h.item_id, h.given_by, h.received_by, 'Handed over to verified owner', h.handed_at
FROM handovers h;

UPDATE items i JOIN handovers h ON h.item_id = i.item_id
SET i.status = 'handed_over', i.current_custodian_id = h.received_by;      -- verified -> handed_over

-- items 41..55: owner confirmed receipt
UPDATE items SET status = 'returned' WHERE item_id BETWEEN 41 AND 55;      -- handed_over -> returned

-- first custody entry should carry the time the item was found, not "now"
UPDATE custody_log cl JOIN items i ON i.item_id = cl.item_id
SET cl.moved_at = i.found_at
WHERE cl.from_user_id IS NULL;

DROP TEMPORARY TABLE seed_items;

-- ---------------- row counts ----------------
SELECT 'users' t, COUNT(*) FROM users UNION ALL
SELECT 'items', COUNT(*) FROM items UNION ALL
SELECT 'claims', COUNT(*) FROM claims UNION ALL
SELECT 'verification_attempts', COUNT(*) FROM verification_attempts UNION ALL
SELECT 'handovers', COUNT(*) FROM handovers UNION ALL
SELECT 'custody_log', COUNT(*) FROM custody_log UNION ALL
SELECT 'audit_log', COUNT(*) FROM audit_log;
SELECT status, COUNT(*) AS items FROM items GROUP BY status;
