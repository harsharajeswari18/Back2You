-- Back2You: stored procedures (run AFTER back2you_schema.sql)
-- perform_handover already exists in back2you_schema.sql
USE back2you;

DELIMITER $$

-- ---------------------------------------------------------------
-- register_item: a finder registers an item; staff/custodian holds it
-- ---------------------------------------------------------------
DROP PROCEDURE IF EXISTS register_item$$
CREATE PROCEDURE register_item(
  IN  p_finder_id    INT,
  IN  p_custodian_id INT,
  IN  p_category_id  INT,
  IN  p_location_id  INT,
  IN  p_title        VARCHAR(120),
  IN  p_description  TEXT,
  IN  p_color        VARCHAR(30),
  IN  p_found_at     DATETIME,
  OUT p_item_id      INT
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  IF p_found_at > NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'found_at cannot be in the future';
  END IF;

  SET @app_user_id = p_finder_id;
  START TRANSACTION;

  INSERT INTO items (finder_id, category_id, location_id, title, description,
                     color, found_at, current_custodian_id)
  VALUES (p_finder_id, p_category_id, p_location_id, p_title, p_description,
          p_color, p_found_at, p_custodian_id);
  SET p_item_id = LAST_INSERT_ID();   -- first custody + audit rows come from triggers

  COMMIT;
END$$

-- ---------------------------------------------------------------
-- submit_claim: an owner claims an item (item moves to 'claimed' via trigger)
-- ---------------------------------------------------------------
DROP PROCEDURE IF EXISTS submit_claim$$
CREATE PROCEDURE submit_claim(
  IN  p_item_id          INT,
  IN  p_claimant_id      INT,
  IN  p_description      TEXT,
  IN  p_lost_at          DATETIME,
  IN  p_lost_location_id INT,
  OUT p_claim_id         INT
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_finder INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT status, finder_id INTO v_status, v_finder
  FROM items WHERE item_id = p_item_id FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item not found';
  END IF;
  IF v_status NOT IN ('registered','claimed') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item is not open for claims';
  END IF;
  IF v_finder = p_claimant_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Finder cannot claim their own item';
  END IF;

  SET @app_user_id = p_claimant_id;
  INSERT INTO claims (item_id, claimant_id, description, lost_at, lost_location_id)
  VALUES (p_item_id, p_claimant_id, p_description, p_lost_at, p_lost_location_id);
  SET p_claim_id = LAST_INSERT_ID();

  COMMIT;
END$$

-- ---------------------------------------------------------------
-- verify_claim: staff records a verification attempt.
--   pass -> claim + item become 'verified', competing pending claims rejected
--   fail -> claim rejected; item goes back to 'registered' if no claims remain
-- ---------------------------------------------------------------
DROP PROCEDURE IF EXISTS verify_claim$$
CREATE PROCEDURE verify_claim(
  IN p_claim_id INT,
  IN p_staff_id INT,
  IN p_method   VARCHAR(20),
  IN p_notes    VARCHAR(255),
  IN p_result   VARCHAR(10)
)
BEGIN
  DECLARE v_role VARCHAR(10);
  DECLARE v_item_id INT;
  DECLARE v_claim_status VARCHAR(20);
  DECLARE v_item_status VARCHAR(20);
  DECLARE v_pending INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SELECT role INTO v_role FROM users WHERE user_id = p_staff_id;
  IF v_role IS NULL OR v_role NOT IN ('staff','admin') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only staff or admin can verify claims';
  END IF;

  START TRANSACTION;

  SELECT item_id, status INTO v_item_id, v_claim_status
  FROM claims WHERE claim_id = p_claim_id FOR UPDATE;
  IF v_item_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Claim not found';
  END IF;

  SELECT status INTO v_item_status
  FROM items WHERE item_id = v_item_id FOR UPDATE;

  IF v_claim_status <> 'pending' OR v_item_status <> 'claimed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Claim is not awaiting verification';
  END IF;

  SET @app_user_id = p_staff_id;

  INSERT INTO verification_attempts (claim_id, staff_id, method, notes, result)
  VALUES (p_claim_id, p_staff_id, p_method, p_notes, p_result);

  IF p_result = 'pass' THEN
    UPDATE claims SET status = 'verified' WHERE claim_id = p_claim_id;
    UPDATE claims SET status = 'rejected'
      WHERE item_id = v_item_id AND claim_id <> p_claim_id AND status = 'pending';
    UPDATE items SET status = 'verified' WHERE item_id = v_item_id;
  ELSE
    UPDATE claims SET status = 'rejected' WHERE claim_id = p_claim_id;
    SELECT COUNT(*) INTO v_pending FROM claims
      WHERE item_id = v_item_id AND status = 'pending';
    IF v_pending = 0 THEN
      UPDATE items SET status = 'registered' WHERE item_id = v_item_id;
    END IF;
  END IF;

  COMMIT;
END$$

-- ---------------------------------------------------------------
-- confirm_return: the owner confirms receipt -> item becomes 'returned'
-- ---------------------------------------------------------------
DROP PROCEDURE IF EXISTS confirm_return$$
CREATE PROCEDURE confirm_return(
  IN p_item_id INT,
  IN p_user_id INT
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_receiver INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT status INTO v_status FROM items WHERE item_id = p_item_id FOR UPDATE;
  IF v_status IS NULL OR v_status <> 'handed_over' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item is not awaiting return confirmation';
  END IF;

  SELECT received_by INTO v_receiver FROM handovers
  WHERE item_id = p_item_id ORDER BY handed_at DESC, handover_id DESC LIMIT 1;
  IF v_receiver IS NULL OR v_receiver <> p_user_id THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Only the person who received the item can confirm return';
  END IF;

  SET @app_user_id = p_user_id;
  UPDATE items SET status = 'returned' WHERE item_id = p_item_id;

  COMMIT;
END$$

DELIMITER ;
