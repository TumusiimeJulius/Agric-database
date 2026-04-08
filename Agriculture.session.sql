CREATE TABLE Person (
    person_id     INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    phone         VARCHAR(15) UNIQUE NOT NULL,
    gender        ENUM('Male','Female','Other') NOT NULL,
    dob           DATE NOT NULL,
    national_id   VARCHAR(20) UNIQUE NOT NULL
);
CREATE TABLE Farmer (
    farmer_id     INT PRIMARY KEY,
    registration_date DATE DEFAULT (CURDATE()),
    education_level   ENUM('None','Primary','Secondary','Tertiary'),
    FOREIGN KEY (farmer_id) REFERENCES Person(person_id) ON DELETE CASCADE
);
-- EXTENSION WORKER (Specialization of Person)
CREATE TABLE ExtensionWorker (
    worker_id     INT PRIMARY KEY,
    employee_no   VARCHAR(20) UNIQUE NOT NULL,
    qualification VARCHAR(100),
    district      VARCHAR(50) NOT NULL,
    hire_date     DATE NOT NULL,
    FOREIGN KEY (worker_id) REFERENCES Person(person_id) ON DELETE CASCADE
);
-----FARM
CREATE TABLE Farm (
    farm_id       INT AUTO_INCREMENT PRIMARY KEY,
    farmer_id     INT NOT NULL,
    village       VARCHAR(100),
    sub_county    VARCHAR(100),
    district      VARCHAR(100) NOT NULL,
    size_acres    DECIMAL(6,2) CHECK (size_acres > 0),
    gps_lat       DECIMAL(9,6),
    gps_long      DECIMAL(9,6),
    FOREIGN KEY (farmer_id) REFERENCES Farmer(farmer_id)
);
-- PRODUCTION
CREATE TABLE Production (
    production_id INT AUTO_INCREMENT PRIMARY KEY,
    farm_id       INT NOT NULL,
    season        ENUM('Season A','Season B') NOT NULL,
    year          YEAR NOT NULL,
    quantity_kg   DECIMAL(10,2) CHECK (quantity_kg >= 0),
    quality_grade ENUM('A','B','C') NOT NULL,
    recorded_date DATE DEFAULT (CURDATE()),
    FOREIGN KEY (farm_id) REFERENCES Farm(farm_id)
);

-- MINISTRY STORE
CREATE TABLE MinistryStore (
    store_id      INT AUTO_INCREMENT PRIMARY KEY,
    store_name    VARCHAR(100) NOT NULL,
    district      VARCHAR(100) NOT NULL,
    stock_qty     INT DEFAULT 0 CHECK (stock_qty >= 0)
);

-- INPUT TYPE
CREATE TABLE Input (
    input_id      INT AUTO_INCREMENT PRIMARY KEY,
    input_name    VARCHAR(100) NOT NULL,
    input_type    ENUM('Seedlings','Fertilizer','Pesticide','Tool') NOT NULL,
    unit          VARCHAR(20),
    store_id      INT,
    FOREIGN KEY (store_id) REFERENCES MinistryStore(store_id)
);

-- FARMER_INPUT (M:N resolved)
CREATE TABLE FarmerInput (
    fi_id         INT AUTO_INCREMENT PRIMARY KEY,
    farmer_id     INT NOT NULL,
    input_id      INT NOT NULL,
    quantity      INT NOT NULL CHECK (quantity > 0),
    date_given    DATE NOT NULL,
    given_by      INT,  -- ExtensionWorker
    FOREIGN KEY (farmer_id) REFERENCES Farmer(farmer_id),
    FOREIGN KEY (input_id) REFERENCES Input(input_id),
    FOREIGN KEY (given_by) REFERENCES ExtensionWorker(worker_id)
);

-- ASSIGNMENT (Farmer ↔ ExtensionWorker)
CREATE TABLE Assignment (
    assignment_id INT AUTO_INCREMENT PRIMARY KEY,
    farmer_id     INT NOT NULL,
    worker_id     INT NOT NULL,
    assigned_date DATE DEFAULT (CURDATE()),
    is_active     BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (farmer_id) REFERENCES Farmer(farmer_id),
    FOREIGN KEY (worker_id) REFERENCES ExtensionWorker(worker_id)
);

-- ADVISORY VISIT
CREATE TABLE AdvisoryVisit (
    visit_id      INT AUTO_INCREMENT PRIMARY KEY,
    farmer_id     INT NOT NULL,
    worker_id     INT NOT NULL,
    visit_date    DATE NOT NULL,
    recommendations TEXT,
    follow_up_date DATE,
    FOREIGN KEY (farmer_id) REFERENCES Farmer(farmer_id),
    FOREIGN KEY (worker_id) REFERENCES ExtensionWorker(worker_id)
);

-- SYSTEM USERS
CREATE TABLE SystemUser (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    person_id     INT UNIQUE,
    username      VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('Admin','ExtensionWorker','Farmer') NOT NULL,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (person_id) REFERENCES Person(person_id)
);
ALTER TABLE Assignment 
ADD CONSTRAINT unique_assignment UNIQUE(farmer_id, worker_id);

ALTER TABLE Production 
ADD CONSTRAINT unique_production UNIQUE(farm_id, season, year);

ALTER TABLE FarmerInput 
ADD CONSTRAINT unique_farmer_input UNIQUE(farmer_id, input_id, date_given);

ALTER TABLE Input 
MODIFY store_id INT NOT NULL;

ALTER TABLE FarmerInput 
MODIFY given_by INT NOT NULL;




--MILESTONE 4: Security & Automation 
--Views

-- Ministry sees all farmer production summaries
CREATE VIEW vw_FarmerProduction AS
SELECT p.full_name, f.district, pr.season, pr.year,
       SUM(pr.quantity_kg) AS total_kg
FROM Farmer fa
JOIN Person p ON fa.farmer_id = p.person_id
JOIN Farm f ON f.farmer_id = fa.farmer_id
JOIN Production pr ON pr.farm_id = f.farm_id
GROUP BY fa.farmer_id, pr.season, pr.year;

-- Extension worker sees only their assigned farmers
CREATE VIEW vw_MyFarmers AS
SELECT p.full_name, p.phone, f.district, a.assigned_date
FROM Assignment a
JOIN Farmer fa ON a.farmer_id = fa.farmer_id
JOIN Person p ON fa.farmer_id = p.person_id
JOIN Farm f ON f.farmer_id = fa.farmer_id
WHERE a.is_active = TRUE;
---user role and privillages
-- Admin user
CREATE USER 'agri_admin'@'localhost' IDENTIFIED BY 'Admin@1234';
GRANT ALL PRIVILEGES ON agri_db.* TO 'agri_admin'@'localhost';

-- Extension worker user
CREATE USER 'ext_worker'@'localhost' IDENTIFIED BY 'Worker@5678';
GRANT SELECT, INSERT, UPDATE ON agri_db.AdvisoryVisit TO 'ext_worker'@'localhost';
GRANT SELECT ON agri_db.vw_MyFarmers TO 'ext_worker'@'localhost';

-- Read-only ministry viewer
CREATE USER 'ministry_viewer'@'localhost' IDENTIFIED BY 'View@9999';
GRANT SELECT ON agri_db.vw_FarmerProduction TO 'ministry_viewer'@'localhost';

FLUSH PRIVILEGES;

----stored procrdures

-- Register a new farmer
CREATE PROCEDURE sp_RegisterFarmer(
    IN p_name VARCHAR(100), IN p_phone VARCHAR(15),
    IN p_gender ENUM('Male','Female','Other'),
    IN p_dob DATE, IN p_nin VARCHAR(20),
    IN p_education ENUM('None','Primary','Secondary','Tertiary')
)
BEGIN
    DECLARE new_id INT;
    INSERT INTO Person(full_name, phone, gender, dob, national_id)
    VALUES (p_name, p_phone, p_gender, p_dob, p_nin);
    SET new_id = LAST_INSERT_ID();
    INSERT INTO Farmer(farmer_id, education_level)
    VALUES (new_id, p_education);
    SELECT new_id AS new_farmer_id;
END;

---TRIGGERS

-- Auto-log when production record is added
CREATE TABLE ProductionLog (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    farm_id INT, action_time DATETIME, logged_qty DECIMAL(10,2)
);

CREATE TRIGGER trg_AfterProductionInsert
AFTER INSERT ON Production
FOR EACH ROW
BEGIN
    INSERT INTO ProductionLog(farm_id, action_time, logged_qty)
    VALUES (NEW.farm_id, NOW(), NEW.quantity_kg);
END;

CREATE TRIGGER trg_PreventMultipleAssignments
BEFORE INSERT ON Assignment
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM Assignment 
        WHERE farmer_id = NEW.farmer_id AND is_active = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Farmer already has an active extension worker';
    END IF;
END;

-- BACKUP AND RECOVERY STRATEGY

-- Backup command
-- mysqldump -u root -p agri_db > agri_backup.sql

-- Restore command
-- mysql -u root -p agri_db < agri_backup.sql

--------TESTING THE SYSTEM

----Insert Persons
INSERT INTO Person(full_name, phone, gender, dob, national_id)
VALUES 
('John Doe', '0700000001', 'Male', '1990-01-01', 'NIN001'),
('Mary Naki', '0700000002', 'Female', '1995-05-10', 'NIN002');

------Make them Farmer & Extension Worker

-- John → Farmer
INSERT INTO Farmer(farmer_id, education_level)
VALUES (1, 'Primary');

-- Mary → Extension Worker
INSERT INTO ExtensionWorker(worker_id, employee_no, qualification, district, hire_date)
VALUES (2, 'EMP001', 'Agriculture Diploma', 'Mukono', '2022-01-01');
----add farm 
INSERT INTO Farm(farmer_id, village, sub_county, district, size_acres)
VALUES (1, 'Katosi', 'Mukono TC', 'Mukono', 2.5);
----add production
INSERT INTO Production(farm_id, season, year, quantity_kg, quality_grade)
VALUES (1, 'Season A', 2025, 500, 'A');

-----Add Store + Input
INSERT INTO MinistryStore(store_name, district, stock_qty)
VALUES ('Mukono Store', 'Mukono', 1000);

INSERT INTO Input(input_name, input_type, unit, store_id)
VALUES ('Coffee Seedlings', 'Seedlings', 'Pieces', 1);
-----assign extension worker to farmer
INSERT INTO Assignment(farmer_id, worker_id)
VALUES (1, 2);
----Give Inputs to Farmer
INSERT INTO FarmerInput(farmer_id, input_id, quantity, date_given, given_by)
VALUES (1, 1, 100, '2026-04-01', 2);
----advisory visit
INSERT INTO AdvisoryVisit(farmer_id, worker_id, visit_date, recommendations)
VALUES (1, 2, '2026-04-05', 'Use better irrigation methods');

---STEP 2: Test Your Views
----Farmer Production Report
SELECT * FROM vw_FarmerProduction;
----Assigned Farmers
SELECT * FROM vw_MyFarmers;


----Test Stored Procedure
CALL sp_RegisterFarmer(
    'Peter Kato',
    '0700000003',
    'Male',
    '1992-02-02',
    'NIN003',
    'Secondary'
);
----Test Production Trigger
INSERT INTO Production(farm_id, season, year, quantity_kg, quality_grade)
VALUES (1, 'Season B', 2025, 300, 'B');
-----check

SELECT * FROM ProductionLog;

-----Test Assignment Restriction
INSERT INTO Assignment(farmer_id, worker_id)
VALUES (1, 2); -- This should fail due to the trigger preventing multiple active assignments
---Test Security
SELECT * FROM vw_MyFarmers; -- Should show assigned farmers for ext_worker
SELECT * FROM vw_FarmerProduction; -- Should show production summary for ministry_viewer

