-- Back2You: important queries, procedure demos and tests
-- Run after schema -> procedures -> seed
USE back2you;

-- =====================================================================
-- A. REPORT QUERIES (JOIN, GROUP BY, HAVING, ORDER BY, subqueries)
-- =====================================================================

-- A1. JOIN: latest registered items with category, location and finder
SELECT i.item_id, i.title, c.name AS category, l.name AS location,
       u.full_name AS finder, i.status
FROM items i
JOIN categories c ON c.category_id = i.category_id
JOIN locations  l ON l.location_id = i.location_id
JOIN users      u ON u.user_id     = i.finder_id
ORDER BY i.found_at DESC
LIMIT 10;

-- A2. GROUP BY + HAVING: categories with many items still waiting for an owner
SELECT c.name AS category, COUNT(*) AS waiting_items
FROM items i JOIN categories c ON c.category_id = i.category_id
WHERE i.status IN ('registered','claimed')
GROUP BY c.category_id, c.name
HAVING COUNT(*) > 15
ORDER BY waiting_items DESC;

-- A3. Correlated subquery: items with competing pending claims
SELECT i.item_id, i.title,
       (SELECT COUNT(*) FROM claims c
         WHERE c.item_id = i.item_id AND c.status = 'pending') AS pending_claims
FROM items i
WHERE (SELECT COUNT(*) FROM claims c
        WHERE c.item_id = i.item_id AND c.status = 'pending') > 1;

-- A4. Staff verification workload and pass rate
SELECT u.full_name AS staff, COUNT(*) AS attempts,
       SUM(v.result = 'pass') AS passed,
       ROUND(100 * SUM(v.result = 'pass') / COUNT(*), 1) AS pass_pct
FROM verification_attempts v
JOIN users u ON u.user_id = v.staff_id
GROUP BY u.user_id, u.full_name
HAVING COUNT(*) >= 5
ORDER BY attempts DESC;

-- A5. Average hours from found to handed over, by location type
SELECT l.type AS location_type,
       COUNT(*) AS handovers,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, i.found_at, h.handed_at)), 1) AS avg_hours
FROM handovers h
JOIN items i     ON i.item_id = h.item_id
JOIN locations l ON l.location_id = i.location_id
GROUP BY l.type
ORDER BY avg_hours;

-- A6. NOT EXISTS subquery: users who claimed items but never got one verified
SELECT u.user_id, u.full_name
FROM users u
WHERE EXISTS     (SELECT 1 FROM claims c WHERE c.claimant_id = u.user_id)
  AND NOT EXISTS (SELECT 1 FROM claims c
                   WHERE c.claimant_id = u.user_id AND c.status = 'verified')
LIMIT 10;

-- A7. Views
SELECT * FROM v_admin_dashboard;
SELECT * FROM v_unclaimed_items ORDER BY days_waiting DESC LIMIT 10;
SELECT * FROM v_item_timeline WHERE item_id = 41 ORDER BY moved_at;

-- A8. Audit trail of one item, with who made each change
SELECT a.audit_id, a.action, a.old_value, a.new_value, u.full_name AS changed_by
FROM audit_log a LEFT JOIN users u ON u.user_id = a.changed_by
WHERE a.table_name = 'items' AND a.record_id = 41
ORDER BY a.audit_id;

-- A9. FULLTEXT search on item text
SELECT item_id, title, status,
       MATCH(title, description) AGAINST('black leather wallet library') AS score
FROM items
WHERE MATCH(title, description) AGAINST('black leather wallet library')
ORDER BY score DESC
LIMIT 10;

-- =====================================================================
-- B. DML DEMOS (INSERT / UPDATE / DELETE through the full lifecycle)
-- =====================================================================
SET @item = NULL, @claim = NULL;

-- B1. register -> claim -> verify -> handover -> return (all via procedures)
CALL register_item(11, 3, 2, 8, 'brown leather wallet',
     'Brown leather wallet with two cards, found on a library table',
     'brown', NOW() - INTERVAL 1 HOUR, @item);
CALL submit_claim(@item, 12, 'I lost my brown leather wallet in the library',
     NOW() - INTERVAL 5 HOUR, 8, @claim);
CALL verify_claim(@claim, 3, 'secret_detail', 'Described both cards correctly', 'pass');
CALL perform_handover(@claim, 3, 'signature', 'sig_demo_001');
CALL confirm_return(@item, 12);
SELECT item_id, status FROM items WHERE item_id = @item;
SELECT * FROM v_item_timeline WHERE item_id = @item ORDER BY moved_at;

-- B2. UPDATE and DELETE
UPDATE users SET phone = '9000000011' WHERE user_id = 11;
DELETE FROM audit_log WHERE changed_at < NOW() - INTERVAL 5 YEAR;   -- retention clean-up

-- =====================================================================
-- C. NEGATIVE TESTS (each statement below must FAIL; screenshot the errors)
-- =====================================================================
-- C1. illegal state jump (registered -> returned)
UPDATE items SET status = 'returned' WHERE item_id = 200;
-- C2. handover before verification
CALL perform_handover(120, 3, 'signature', 'x');
-- C3. finder claims own item
CALL submit_claim(200, 11 + 200 % 50, 'It is mine, I lost it today', NOW(), 1, @claim);
-- C4. a normal user tries to verify a claim
CALL verify_claim(1, 15, 'secret_detail', 'x', 'pass');
-- C5. claim on an item that is already returned
CALL submit_claim(41, 30, 'This is my item, honestly', NOW(), 1, @claim);
-- C6. wrong person confirms return
CALL confirm_return(60, 11);
-- C7. CHECK constraints
INSERT INTO users (full_name,email,phone,password_hash) VALUES ('Bad','not-an-email','1','x');
INSERT INTO items (finder_id,category_id,location_id,title,description,found_at,current_custodian_id)
VALUES (11,1,1,'ab','too short',NOW(),3);
-- C8. FK violation
INSERT INTO claims (item_id,claimant_id,description,lost_at) VALUES (99999,11,'does not exist at all',NOW());
-- C9. duplicate claim by the same person
INSERT INTO claims (item_id,claimant_id,description,lost_at)
SELECT item_id, claimant_id, 'duplicate claim attempt', NOW() FROM claims WHERE claim_id = 1;
-- C10. handing an item to yourself
INSERT INTO handovers (item_id,claim_id,given_by,received_by,proof_type,proof_ref)
VALUES (150,150,11,11,'otp','x');

-- =====================================================================
-- D. INDEX EVIDENCE (copy the EXPLAIN output into your report)
-- =====================================================================
-- D1. status index
DROP INDEX idx_items_status ON items;
EXPLAIN SELECT item_id, title FROM items WHERE status = 'verified';
CREATE INDEX idx_items_status ON items(status);
EXPLAIN SELECT item_id, title FROM items WHERE status = 'verified';

-- D2. FULLTEXT vs LIKE
EXPLAIN SELECT item_id FROM items WHERE description LIKE '%wallet%';
EXPLAIN SELECT item_id FROM items WHERE MATCH(title, description) AGAINST('wallet');
-- Note: with only 300 rows the optimizer may still choose a table scan. Add
-- "FORCE INDEX (idx_items_status)" or seed 50k rows to show a clear difference.
