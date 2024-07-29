Drop DATABASE if exists PROJECT;
CREATE DATABASE IF NOT EXISTS PROJECT;
USE PROJECT;

CREATE TABLE IF NOT EXISTS companies (
	company_ID numeric(6),
    comp_name varchar(90) not null,
    city varchar(90) not null,
    
    primary key (company_id)
);

CREATE TABLE IF NOT EXISTS owners (
	owner_ID numeric(6),
    first_name varchar(30) not null,
    last_name varchar(30) not null,
    contact varchar(16) unique not null,
    
	primary key (owner_ID)
);

CREATE TABLE IF NOT EXISTS properties (
	property_ID numeric(6), 
    owner_ID numeric(6),
	property_TYPE enum('House','Apartment','Condominium','Townhouse','Duplex','Triplex','Quadplex',
    'Villa','Cottage','Mobile Home','Commercial Property','Land/Plot','Industrial Property','Farm/Ranch') not null,
	prop_status enum('Sold', 'On Hold', 'For Sale') not null,   
    city varchar(30) not null,
    size numeric(6) not null,
    listing_price numeric(11) not null,
    
    primary key(property_ID),
	constraint check_positivity_prop
		check(size > 0 and listing_price > 0),
	constraint property_fk2
		foreign key(owner_ID) references owners(owner_ID)
		on delete SET NULL ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS contracts_owner (
	 contract_ID numeric(6),
     property_ID numeric(6),
     company_ID numeric(6),
     date_contract date not null,
     exclusivity enum ('Yes', 'No'),
     aditional_terms varchar(200),
     
     primary key (contract_ID),
	constraint contracts_owner_fk1
		foreign key(company_ID) references companies(company_ID)
		on delete SET NULL ON UPDATE CASCADE,
	constraint contracts_owner_fk2
		foreign key(property_ID) references properties (property_ID)
        on delete SET NULL ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS agents(
	agent_ID numeric(6),
    company_ID numeric(6),
    first_name_agent varchar(20) not null,
    last_name_agent varchar(20) not null,
    contact varchar(18) unique not null,
    comission_rate numeric(2,1),
    
    primary key (agent_ID),
    constraint agent_fk1
		foreign key(company_ID) references companies(company_ID)
		on delete SET NULL ON UPDATE CASCADE,
	CONSTRAINT check_positivity_ag
		CHECK(comission_rate > 0)
);

CREATE TABLE IF NOT EXISTS clients (
	client_ID numeric(6),
    first_name varchar(20) not null,
    last_name varchar(20) not null,
    contact varchar(16) unique not null,
    email varchar(60),
    preferred_property_type enum('House','Apartment','Condominium','Townhouse','Duplex',
                        'Triplex','Quadplex','Villa','Cottage','Mobile Home',
                        'Commercial Property','Land/Plot','Industrial Property','Farm/Ranch'),
                        
    primary key (client_ID)
);

CREATE TABLE IF NOT EXISTS appointments (
	appointment_ID numeric(6),
    agent_ID numeric(6),
    client_ID numeric(6),
    property_ID numeric(6),
    date_appointment date not null,
    type_appointment enum('Viewing','Meeting','') not null,
    
	primary key (appointment_ID),
    constraint appointments_fk1
		foreign key(agent_ID) references agents(agent_ID)
		on delete SET NULL ON UPDATE CASCADE,
	constraint appointments_fk2
		foreign key(client_ID) references clients(client_ID)
		on delete SET NULL ON UPDATE CASCADE,
	constraint appointments_fk3
		foreign key(property_ID) references properties(property_ID)
        on delete SET NULL ON UPDATE CASCADE
);


CREATE TABLE IF NOT EXISTS transactions (
	transaction_ID numeric(6),
    property_ID numeric(6),
    client_ID numeric(6),
    agent_ID numeric(6),
    review_process numeric(2,1),
    date_transaction date not null,
    terms_contract text,
    
    primary key(transaction_id),
	constraint transactions_fk1
		foreign key(property_ID) references properties(property_ID)
		on delete SET NULL ON UPDATE CASCADE,
	constraint transactions_fk2
		foreign key(client_ID) references clients(client_ID)
		on delete SET NULL ON UPDATE CASCADE,
	constraint transactions_fk3
		foreign key(agent_ID) references agents(agent_ID)
        on delete SET NULL ON UPDATE CASCADE
);

	
CREATE TABLE IF NOT EXISTS visits( 
	visit_ID numeric(6),
    appointment_id numeric(6),
    outcome enum('Y','N','Waiting') not null,
    
    primary key(visit_ID),
	constraint visits_fk1
		foreign key(appointment_id) references appointments(appointment_id)
);

CREATE TABLE IF NOT EXISTS reviews( 
	review_ID numeric(5), 
    property_ID numeric(6),
    client_ID numeric(6),
    rating_property numeric(2,1), 
    review_comment text,
    date_review date not null,
    
    primary key(review_ID),
    constraint reviews_fk1
		foreign key(property_ID) references properties(property_ID)
		on delete SET NULL ON UPDATE CASCADE,
	constraint reviews_fk2
		foreign key(client_ID) references clients(client_ID)
        on delete SET NULL ON UPDATE CASCADE        
);


CREATE TABLE IF NOT EXISTS log_transactions (
    log_ID INT AUTO_INCREMENT,
    event_date date,
    transaction_id numeric(6),
    event_type varchar(50),
    details varchar(100),
    
    primary key (log_id),
    CONSTRAINT log_transactions_fk1
        FOREIGN KEY(transaction_id) REFERENCES transactions(transaction_ID)
);

###########   TRIGGERS ###########

-- (1)

DELIMITER //
CREATE TRIGGER log_transaction_insert 
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO log_transactions (event_date, transaction_id, event_type, details)
    VALUES (NEW.date_transaction, NEW.transaction_ID, 'Transaction Inserted', CONCAT('New transaction added: ', NEW.transaction_ID));
END;
//
DELIMITER ;

-- (2)

DELIMITER //
CREATE TRIGGER update_prop_status
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM properties WHERE property_ID = NEW.property_ID) THEN
        UPDATE properties
        SET prop_status = 'Sold'
        WHERE property_ID = NEW.property_ID;
    END IF;
END;
//
DELIMITER ;

-- (3)

DELIMITER //
CREATE TRIGGER prop_status_sold
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE propSold VARCHAR(10);
    
    SELECT prop_status INTO propSold
    FROM properties
    WHERE property_ID = NEW.property_ID;
    
    IF propSold = 'Sold' THEN
        SET @error_message = CONCAT('Cannot perform a transaction on Property ID: ', NEW.property_ID, ' that is already sold.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @error_message;
    END IF;
END;
//
DELIMITER ;

-- (4)

DELIMITER //
CREATE TRIGGER check_date_order
BEFORE INSERT ON appointments
FOR EACH ROW
BEGIN
    IF NEW.date_appointment <= (
        SELECT MIN(date_contract) FROM contracts_owner WHERE property_ID = NEW.property_ID
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Date of appointment must be after the contract owner date for the property.';
    END IF;
END;
//
DELIMITER ;

-- (5)

DELIMITER //
CREATE TRIGGER review_date_validation
BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
    DECLARE trans_date DATE;

    SELECT date_transaction INTO trans_date
    FROM transactions
    WHERE property_ID = NEW.property_ID;

    IF NEW.date_review <= trans_date THEN
        SET @error_message = CONCAT('Review ID: ', NEW.review_ID, ' - Review date must be after transaction date.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @error_message;
    END IF;
END;
//
DELIMITER ;

-- (6)

DELIMITER //
CREATE TRIGGER update_prop_status_on_house_contract
AFTER INSERT ON contracts_owner
FOR EACH ROW
BEGIN
    DECLARE prop_type VARCHAR(50);

    -- Fetch the property type associated with the new contract
    SELECT property_TYPE INTO prop_type
    FROM properties
    WHERE property_ID = NEW.property_ID;

    -- Check if the property is set as a house and update the status
    IF prop_type = 'House' THEN
        UPDATE properties
        SET prop_status = 'For Sale'
        WHERE property_ID = NEW.property_ID;
    END IF;
END;
//
DELIMITER ;

-- (7)

DELIMITER //
CREATE TRIGGER exclusivity_sold_check
BEFORE INSERT ON contracts_owner
FOR EACH ROW
BEGIN
    DECLARE property_exclusivity_count INT;
    DECLARE property_no_exclusivity_count INT;

    -- Check if there are contracts with exclusivity for the same date
    SELECT COUNT(*)
    INTO property_exclusivity_count
    FROM contracts_owner
    WHERE date_contract = NEW.date_contract AND exclusivity = 'Yes';

    -- Check if there are contracts without exclusivity for the same date
    SELECT COUNT(*)
    INTO property_no_exclusivity_count
    FROM contracts_owner
    WHERE date_contract = NEW.date_contract AND exclusivity = 'No';

    IF property_exclusivity_count > 0 OR (property_no_exclusivity_count > 0 AND NEW.exclusivity = 'Yes') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot set exclusivity if contracts without exclusivity exist for the same date, or property with exclusivity by another company on the same date.';
    END IF;
END;
//
DELIMITER ;



######### TEST_TRIGGERS ###########


/* We will try to test our triggers through several ways, 
not only with "single" inserts but also with batch inserts: */

-- LET'S CREATE A SMALLER DATASET FOR TO TEST OUR TRIGGERS

-- 1) TRIGGER update_prop_status
-- Originally we have our log_transactions table empty and every time that we inset a transaction (meaning that a house has been sold), a new row its inserted on this table

select * from log_transactions;

INSERT INTO companies (company_ID, comp_name, city)
VALUES (0165, 'Realty', 'Alabama');
INSERT INTO owners (owner_ID, first_name, last_name, contact)
VALUES (1254, 'John', 'Doe', '+1 23456789');
INSERT INTO properties (property_ID, owner_ID, property_TYPE,prop_status, city, size, listing_price)
VALUES (2651,  1254, 'House', 'For Sale','Hawaii', 2000, 500000);
INSERT INTO contracts_owner (contract_ID, property_ID, company_ID, date_contract, exclusivity, aditional_terms)
VALUES (8001, 2651, 0165, '2019-03-20', 'Yes', 'Property advertising terms');
INSERT INTO agents (agent_ID, company_ID, first_name_agent, last_name_agent, contact, comission_rate)
VALUES (3147, 165, 'Michael', 'Smith', '+1 234567891', 5);
INSERT INTO clients (client_ID, first_name, last_name, contact, email, preferred_property_type)
VALUES (4651, 'Alice', 'Johnson', '+1 2345678910', 'alice3@outlook.com', 'House');
INSERT INTO appointments (appointment_ID, agent_ID, client_ID, property_ID, date_appointment, type_appointment)
VALUES (6611, 3147, 4651, 2651, '2019-03-21', 'Viewing');
INSERT INTO transactions (transaction_ID, property_ID, client_ID, agent_ID, review_process, date_transaction)
VALUES (5061, 2651, 4651, 3147, 8, '2019-04-25');
INSERT INTO visits (visit_ID, appointment_id, outcome)
VALUES (9001, 6611, 'Y');
INSERT INTO reviews(review_ID, property_ID, client_ID, rating_property, review_comment, date_review)
VALUES(10851, 2651, 4651, 4, 'Beautiful house with a scenic view!', '2019-05-10');

-- We've not inserted data (directly) on the log_transactions table
-- Let's see if our trigger worked, if so the transaction 5061 will appear on the table
#1) FIRST TRIGGER
select * from log_transactions;

-- Now let's test the same trigger with a batch insertion:
-- Batch insertion for companies
INSERT INTO companies (company_ID, comp_name, city)
VALUES 
    (123, 'Dream Homes', 'New York'),
    (456, 'Elite Realty', 'California'),
    (789, 'Prime Properties', 'Texas');

-- Batch insertion for owners
INSERT INTO owners (owner_ID, first_name, last_name, contact)
VALUES 
    (7890, 'Jane', 'Smith', '+1 9876543210'),
    (3456, 'Chris', 'Williams', '+44 7456234567'),
    (2345, 'Sophia', 'Brown', '+33 6123456789');

-- Batch insertion for properties
INSERT INTO properties (property_ID, owner_ID, property_TYPE, prop_status, city, size, listing_price)
VALUES  
    (9876, 7890, 'Apartment', 'For Sale', 'New York', 1200, 800000),
    (6543, 3456, 'House', 'For Sale', 'California', 2500, 1200000),
    (5432, 2345, 'Condominium', 'For Sale', 'Texas', 1800, 950000);

-- Batch insertion for contracts_owner
INSERT INTO contracts_owner (contract_ID, property_ID, company_ID, date_contract, exclusivity, aditional_terms)
VALUES  
    (9001, 9876, 123, '2019-02-15', 'Yes', 'Exclusive marketing rights'),
    (9002, 6543, 456, '2019-05-20', 'No', 'Standard terms'),
    (9003, 5432, 789, '2019-07-10', 'Yes', 'Property advertising terms');

-- Batch insertion for agents
INSERT INTO agents (agent_ID, company_ID, first_name_agent, last_name_agent, contact, comission_rate)
VALUES  
    (1111, 123, 'Daniel', 'Miller', '+1 8765432109', 4.5),
    (2222, 456, 'Jessica', 'Taylor', '+44 777888999', 3.8),
    (3333, 789, 'David', 'Anderson', '+33 666555444', 5.2);

-- Batch insertion for clients
INSERT INTO clients (client_ID, first_name, last_name, contact, email, preferred_property_type)
VALUES  
    (9999, 'Olivia', 'Johnson', '+1 9876543210', 'olivia.j@email.com', 'Condominium'),
    (8888, 'Matthew', 'White', '+44 7456234567', 'matthew.w@email.com', 'House'),
    (7777, 'Lily', 'Davis', '+33 6123456789', 'lily.d@email.com', 'Apartment');

-- Batch insertion for appointments
INSERT INTO appointments (appointment_ID, agent_ID, client_ID, property_ID, date_appointment, type_appointment)
VALUES  
    (5555, 1111, 9999, 9876, '2019-03-25', 'Viewing'),
    (4444, 2222, 8888, 6543, '2019-06-30', 'Meeting'),
    (3333, 3333, 7777, 5432, '2019-08-20', 'Viewing');

-- Batch insertion for transactions
INSERT INTO transactions (transaction_ID, property_ID, client_ID, agent_ID, review_process, date_transaction, terms_contract)
VALUES  
    (7777, 9876, 9999, 1111, 8.5, '2019-04-15', 'Agreed upon terms'),
    (8888, 6543, 8888, 2222, 7, '2019-07-05', 'Standard terms and conditions'),
    (9999, 5432, 7777, 3333, 9.5, '2019-09-15', 'Exclusive contract signed');

-- Batch insertion for visits
INSERT INTO visits (visit_ID, appointment_id, outcome)
VALUES  
    (1111, 5555, 'Y'),
    (2222, 4444, 'N'),
    (3333, 3333, 'Waiting');

-- Batch insertion for reviews
INSERT INTO reviews(review_ID, property_ID, client_ID, rating_property, review_comment, date_review)
VALUES  
    (1111, 9876, 9999, 4, 'Nice apartment with a great view!', '2019-05-20'),
    (2222, 6543, 8888, 3.5, 'The house needs some repairs.', '2020-07-15'),
    (3333, 5432, 7777, 5, 'Amazing condominium with excellent amenities.', '2022-05-10');

-- Now we will check if the batch insertion worked
select * from log_transactions;


-- 2) TRIGGER update_prop_status
-- we want to check if prop_status is updated to 'Sold' after a transaction

INSERT INTO properties (property_ID, owner_ID, property_TYPE,prop_status, city, size, listing_price)
VALUES (2864,  1254, 'Apartment', 'For Sale', 'California', 200, 250000);

SELECT property_ID, prop_status FROM properties WHERE property_ID = 2864;

INSERT INTO transactions (transaction_ID, property_ID, client_ID, agent_ID, review_process, date_transaction)
VALUES (5864, 2864, 4651, 3147, 8, '2020-11-03');

SELECT property_ID, prop_status FROM properties WHERE property_ID = 2864;

-- originally the property 2864 is for sale and when we add a transaction with these property we update his status
 
 -- Now, as for the first trigger we will try to find if it also works with batch insertions
INSERT INTO properties (property_ID, owner_ID, property_TYPE, prop_status, city, size, listing_price)
VALUES  
    (2865, 1254, 'Apartment', 'For Sale', 'California', 200, 250000),
    (2866, 3456, 'House', 'On Hold', 'Texas', 1800, 950000),
    (2867, 2345, 'Condominium', 'For Sale', 'New York', 1200, 800000);

-- Check the status befor a transction
SELECT property_ID, prop_status FROM properties WHERE property_ID IN (2865, 2866, 2867);

INSERT INTO transactions (transaction_ID, property_ID, client_ID, agent_ID, review_process, date_transaction)
VALUES  
    (5865, 2865, 4651, 3147, 8, '2020-11-03'),
    (5866, 2866, 7777, 3333, 9.5, '2020-11-05'),
    (5867, 2867, 9999, 1111, 8.5, '2020-11-08');
    
-- Here we wanted to check if the prop_status was correctly updated
SELECT property_ID, prop_status FROM properties WHERE property_ID IN (2865, 2866, 2867);
 
 

-- 3) TRIGGER prop_status_sold
-- INSERT a transaction of a property that is already sold

SELECT * FROM transactions WHERE transaction_ID = 5864;

INSERT INTO transactions (transaction_ID, property_ID, client_ID, agent_ID, review_process, date_transaction)
VALUES (5988, 2864, 4651, 3147, 6, '2020-04-25');
-- IT IS SUPPOSED TO GIVE ERROR

-- It is not allowed to sell a house that has the status "Sold"

SELECT * FROM transactions WHERE transaction_ID = 5864;


-- 4) TRIGGER check_date_order
-- A property can only  hold an appointment for a visit after the owner and the agency sign the contect

-- Let's try to make an appointment before this agreement

SELECT * FROM contracts_owner;

-- Let's try to schedule an appointment to before 20/03/2019

INSERT INTO appointments (appointment_ID, agent_ID, client_ID, property_ID, date_appointment, type_appointment)
VALUES (6554, 3147, 4651, 2651, '2019-03-07', 'Viewing');
-- IT IS SUPPOSED TO GIVE ERROR


-- 5) TRIGGER review_date_validation

-- Let's remember the dates of transactions

select * from transactions; # the property 2864 has changed its owner on 03/11/2020
select * from reviews;

INSERT INTO reviews(review_ID, property_ID, client_ID, rating_property, review_comment, date_review)
VALUES(10864, 2864, 4651, 9, 'Good apartment!', '2019-11-01');
-- IT IS SUPPOSED TO GIVE ERROR


-- 6) TRIGGER update_prop_status_on_house_contract
-- Let's test the trigger for property 2651
select * from transactions where property_id = 2651;
select * from properties where property_id = 2651;
-- Let's assume that now the owner of this house is John Legend, and he will set the property for sale so he signs a contract with a comany
-- Then the prop_status must be updated to: "For Sale"

INSERT INTO owners (owner_ID, first_name, last_name, contact)
VALUES (1651, 'John', 'Legend', '+1 630854681');
INSERT INTO contracts_owner (contract_ID, property_ID, company_ID, date_contract, exclusivity, aditional_terms)
VALUES (8651, 2651, 0165, '2019-09-30', 'No', 'Property advertising terms');

select * from transactions;


-- 7) TRIGGER exclusivity_sold_check
select * from contracts_owner where property_id = 2651;
-- There is no exclusivity for the property on sale from John Legend with the company 165
-- The owner can't set his porperty for sale with any other company for that date, for example their rival 631 but they can set contracts without exclusivity

INSERT INTO companies (company_ID, comp_name, city)
VALUES (0995, 'Consul Properties', 'Hawaii'),
		(0631, 'Best Homes Inc.', 'Florida');

INSERT INTO contracts_owner (contract_ID, property_ID, company_ID, date_contract, exclusivity, aditional_terms)
VALUES (8652, 2651, 995, '2019-09-30', 'No', 'Property advertising terms');
-- It is allowed
INSERT INTO contracts_owner (contract_ID, property_ID, company_ID, date_contract, exclusivity, aditional_terms)
VALUES (8653, 2651, 631, '2019-09-30', 'Yes', 'Property advertising terms');
-- IT IS SUPPOSED TO GIVE ERROR FOR THE LAST ROW

select * from contracts_owner where property_id = 2651;


######## DATA ##########

SET SQL_SAFE_UPDATES = 0;
DELETE FROM log_transactions;
DELETE FROM visits;
DELETE FROM reviews;
DELETE FROM appointments;
DELETE FROM contracts_owner;
DELETE FROM transactions;
DELETE FROM properties;
DELETE FROM agents;
DELETE FROM clients;
DELETE FROM owners;
DELETE FROM companies;
SET SQL_SAFE_UPDATES = 1;

INSERT INTO companies (company_ID, comp_name, city)
VALUES 
    (0165, 'Realty', 'Alabama'),
    (0995, 'Consul Properties', 'Hawaii'),
    (0631, 'Best Homes Inc.', 'Florida'),
    (0652, 'Dream Estates', 'California'),
    (0323, 'Elite Realtors', 'New York'),
    (0753, 'Golden Properties', 'California'),
    (0125, 'Sunset Realty', 'Florida'),
    (0787, 'Silver Oak Estates', 'California');

INSERT INTO owners (owner_ID, first_name, last_name, contact)
VALUES 
    (1254, 'John', 'Doe', '+1 23456789'),
    (1561, 'Alice', 'Smith', '+44 987654321'), 
    (1356, 'Bob', 'Johnson', '+33 555555555'), 
    (1478, 'Emma', 'Brown', '+49 333333333'), 
    (1524, 'William', 'Jones', '+61 111111111'),
    (1682, 'Olivia', 'Davis', '+91 444444444'),
    (1097, 'James', 'Wilson', '+81 777777777'),
    (1832, 'Sophia', 'Martinez', '+52 666666666'),
    (1291, 'Ethan', 'Anderson', '+7 999999999'), 
    (1109, 'Ava', 'Garcia', '+34 222222222'), 
    (1114, 'Daniel', 'Lopez', '+52 888888888'),
    (1293, 'Mia', 'Hernandez', '+1 555000555');
    
INSERT INTO properties (property_ID, owner_ID, property_TYPE,prop_status, city, size, listing_price)
VALUES  
    (2651, 1254, 'House', 'For Sale','Hawaii', 2000, 500000),
    (2736, 1561, 'Apartment','For Sale','California', 1500, 300000),
	(2095, 1356, 'Condominium', 'For Sale','Florida', 1800, 400000),
    (2409, 1478, 'House', 'For Sale','California', 2200, 600000),
    (2107, 1293, 'Condominium', 'Sold', 'Chicago', 4000, 925000),
    (2984, 1524, 'Duplex', 'For Sale','Alabama', 2000, 550000),
    (2322, 1682, 'House', 'For Sale','Hawaii', 1900, 485000),
    (2030, 1097, 'Duplex', 'For Sale','Hawaii', 2200, 620000),
    (2146, 1832, 'Villa', 'For Sale','California', 2500, 700000),
    (2036, 1291, 'Commercial Property', 'For Sale','Hawaii', 3000, 800000),
    (2065, 1109, 'Industrial Property', 'For Sale','Hawaii', 2800, 750000),
    (2132, 1114, 'House', 'On Hold','Florida', 2100, 580000),
    (2275, 1293, 'Land/Plot','For Sale','Hawaii', 4000, 950000),
    (2675, 1109, 'Industrial Property', 'Sold', 'Texas', 3500, 900000),
    (2368, 1254, 'House', 'For Sale','Texas', 1800, 450000),
    (2402, 1561, 'Apartment', 'On Hold','Hawaii', 1200, 180000),
    (2568, 1356, 'Condominium', 'For Sale', 'Florida', 2000, 505000),
    (2674, 1478, 'House', 'For Sale', 'Florida', 2500, 700000),
    (2734, 1524, 'Duplex', 'For Sale', 'New York', 2200, 600000),
    (2885, 1682, 'House', 'For Sale', 'Texas', 1900, 480000),
    (2069, 1114, 'Villa', 'Sold', 'Texas', 600, 458000),
    (2903, 1097, 'Duplex', 'For Sale', 'New York', 2000, 550000),
    (2009, 1832, 'Villa', 'For Sale', 'Texas', 2800, 750000),
    (2171, 1291, 'Commercial Property', 'For Sale', 'Nevada', 3000, 805000),
    (2287, 1109, 'Industrial Property', 'For Sale', 'Texas', 3500, 900000),
    (2053, 1114, 'House', 'For Sale', 'Nevada', 2100, 585000),
    (2806, 1293, 'Land/Plot', 'Sold', 'Alaska', 40000, 950000),
    (2288, 1109, 'Apartment', 'For Sale', 'Texas', 2500, 550000),
    (2289, 1114, 'Apartment', 'For Sale', 'Texas', 2100, 375000);

INSERT INTO contracts_owner (contract_ID, property_ID, company_ID, date_contract, exclusivity, aditional_terms)
VALUES
	(8001, 2651, 0165, '2019-03-20', 'Yes', 'Property advertising terms'),
    (8002, 2736, 0995, '2020-06-11', 'No', 'Payment terms and conditions'),
    (8003, 2095, 0631, '2022-03-18', 'Yes', 'Property management details'),
    (8004, 2409, 0652, '2019-05-06', 'No', 'Property maintenance terms'),
    (8005, 2984, 0323, '2019-11-21', 'Yes', 'Leasing terms'),
    (8006, 2322, 0753, '2022-03-15', 'Yes', 'Renovation terms'),
    (8007, 2030, 0125, '2021-01-11', 'No', 'Property usage terms'),
    (8008, 2146, 0787, '2023-02-01', 'Yes', 'Additional property terms'),
    (8009, 2036, 0165, '2023-07-13', 'Yes', 'Property inspection terms'),
    (8010, 2065, 0995, '2020-02-03', 'No', 'Property sale terms'),
    (8011, 2065, 0631, '2020-02-01', 'Yes', 'Property maintenance terms'),
    (8012, 2132, 0753, '2021-12-20', 'No', 'Additional property terms'),
    (8013, 2275, 0125, '2021-01-06', 'Yes', 'Property maintenance terms'),
    (8014, 2368, 0631, '2019-02-15', 'Yes', 'Additional property terms'),
    (8015, 2402, 0652, '2018-12-01', 'No', 'Payment terms and conditions'),
    (8016, 2568, 0323, '2021-12-01', 'No', 'Property usage terms'),
    (8017, 2674, 0753, '2020-03-17', 'No', 'Property usage terms'),
    (8018, 2734, 0323, '2023-01-23', 'No', 'Additional property terms'),
    (8019, 2885, 0995, '2020-11-19', 'Yes', 'Property advertising terms'),
    (8020, 2903, 0995, '2020-10-04', 'Yes', 'Payment terms and conditions'),
    (8021, 2009, 0165, '2021-08-02', 'No', 'Property usage terms'),
    (8022, 2171, 0631, '2023-06-01', 'No', 'Payment terms and conditions'),
    (8023, 2287, 0787, '2022-10-03', 'Yes', 'Property advertising terms'),
    (8724, 2053, 0631, '2021-12-05', 'Yes', 'Payment terms and conditions'),
    (8531, 2107, 0652, '2023-04-12', 'No', 'Property sale terms'),
    (8024, 2288, 0787, '2022-10-13', 'Yes', 'Property advertising terms'),
    (8025, 2289, 0787, '2022-10-23', 'Yes', 'Property advertising terms');
    

INSERT INTO agents (agent_ID, company_ID, first_name_agent, last_name_agent, contact, comission_rate)
VALUES 
    (3147, 165, 'Michael', 'Smith', '+1 234567891', 5),
    (3782, 995, 'Emily', 'Johnson', '+44 987654322', 4.5),
    (3070, 631, 'Daniel', 'Williams', '+33 555555556', 4),
    (3904, 652, 'Sophia', 'Brown', '+49 333333334', 6),
    (3577, 323, 'Matthew', 'Garcia', '+61 111111112', 5.5),
    (3907, 753, 'Olivia', 'Martinez', '+91 444444445', 4),
    (3347, 125, 'James', 'Lopez', '+81 777777778', 3.5),
    (3502, 787, 'Ava', 'Hernandez', '+52 666666667', 6),
    (3313, 165, 'William', 'Anderson', '+7 999999999', 5),
    (3914, 995, 'Sophie', 'Garcia', '+34 222222223', 5),
    (3751, 631, 'Ethan', 'Lopez', '+52 888888889', 4.5),
    (3265, 652, 'Emma', 'Smith', '+1 555000556', 6),
    (3342, 165, 'Liam', 'Hernandez', '+1 555000557', 5),
    (3404, 995, 'Avery', 'Martinez', '+44 987654323', 4.5),
    (3515, 631, 'Harper', 'Garcia', '+33 555555557', 4),
    (3546, 652, 'Logan', 'Lopez', '+49 333333335', 6),
    (3742, 323, 'Evelyn', 'Smith', '+61 111111113', 2.5),
    (3958, 753, 'Mia', 'Williams', '+91 444444446', 4),
    (3249, 125, 'Noah', 'Jones', '+81 777777779', 8.5),
    (3514, 787, 'Luna', 'Brown', '+52 666666668', 9),
    (3361, 165, 'Elijah', 'Davis', '+7 999999998', 5),
    (3242, 787, 'Grace', 'Garcia', '+34 222222224', 7);

INSERT INTO clients (client_ID, first_name, last_name, contact, email, preferred_property_type)
VALUES 
    (4651, 'Alice', 'Johnson', '+1 2345678910', 'alice3@outlook.com', 'House'),
    (4221, 'Michael', 'Smith', '+44 9876543210', 'michael47@gmail.com', 'Apartment'),
    (4384, 'Sophia', 'Brown', '+33 5555555555', 'sophia@gmail.com', 'Condominium'),
    (4405, 'Daniel', 'Garcia', '+49 3333333333', 'daniel@gmail.com', 'Townhouse'),
    (4535, 'Olivia', 'Martinez', '+61 1111111111', 'olivia@outlook.com', 'Duplex'),
    (4689, 'Ethan', 'Jones', '+91 4444444444', 'ethan@outlook.com', 'Triplex'),
    (4787, 'Ava', 'Davis', '+81 7777777777', 'ava@hotmail.com', 'Villa'),
    (4844, 'Noah', 'Anderson', '+52 6666666666', 'noah@outlook.com', 'Cottage'),
    (4989, 'Emma', 'Williams', '+7 9999999999', 'emma@outlook.com', 'Mobile Home'),
    (4105, 'Liam', 'Taylor', '+34 2222222222', 'liam@outlook.com', 'Commercial Property'),
	(4111, 'William', 'Brown', '+1 2345678911', 'william@gmail.com', 'House'),
    (4126, 'Sophie', 'Garcia', '+44 9876543211', 'sophie@gmail.com', 'Apartment'),
    (4139, 'Oliver', 'Martinez', '+33 5555555556', 'oliver@outlook.com', 'Condominium'),
    (4147, 'Grace', 'Johnson', '+49 3333333334', 'grace@hotmail.com', 'Townhouse'),
    (4155, 'Emily', 'Smith', '+61 1111111112', 'emily@outlook.com', 'Duplex'),
    (4169, 'Lucas', 'Jones', '+91 4444444445', 'lucas@hotmail.com', 'Triplex'),
    (4174, 'Avery', 'Davis', '+81 7777777778', 'avery@gmail.com', 'Villa'),
    (4180, 'Isabella', 'Anderson', '+52 6666666667', 'isabella@outlook.com', 'Cottage'),
    (4191, 'Liam', 'Williams', '+7 9999999990', 'liamw@hotmail.com', 'Mobile Home'),
    (4202, 'Aria', 'Garcia', '+34 2222222225', 'aria@hotmail.com', 'Commercial Property');

INSERT INTO appointments (appointment_ID, agent_ID, client_ID, property_ID, date_appointment, type_appointment)
VALUES 
    (6611, 3147, 4651, 2651, '2019-03-21', 'Viewing'),
    (6012, 3782, 4221, 2736, '2020-06-12', ''),
    (6653, 3070, 4384, 2095, '2022-03-19', ''),
    (6324, 3904, 4405, 2409, '2019-05-07', 'Meeting'),
    (6645, 3577, 4535, 2984, '2019-11-22', 'Viewing'),
    (6056, 3907, 4689, 2322, '2022-03-16', ''),
    (6857, 3347, 4787, 2030, '2021-01-12', 'Viewing'),
    (6238, 3502, 4844, 2146, '2023-02-02', ''),
    (6809, 3313, 4989, 2036, '2023-07-14', 'Viewing'),
    (6610, 3914, 4105, 2065, '2020-02-04', 'Meeting'),
    (6061, 3265, 4111, 2132, '2021-12-21', ''),
    (6312, 3342, 4126, 2275, '2021-01-07', 'Meeting'),
    (6713, 3515, 4139, 2368, '2019-02-16', ''),
    (6853, 3546, 4147, 2402, '2018-12-02', 'Meeting'),
    (6820, 3742, 4155, 2568, '2021-12-02', 'Viewing'),
    (6841, 3958, 4169, 2674, '2020-03-18', ''),
    (6960, 3249, 4174, 2734, '2023-01-24', 'Viewing'),
    (6354, 3514, 4180, 2885, '2020-11-20', ''),
    (6901, 3361, 4191, 2903, '2020-10-05', 'Viewing'),
    (6805, 3242, 4202, 2009, '2022-10-04', 'Meeting');
    
INSERT INTO transactions (transaction_ID, property_ID, client_ID, agent_ID, review_process, date_transaction)
VALUES 
    (5061, 2651, 4651, 3147, 8, '2019-04-25'),
    (5202, 2736, 4221, 3782, 1.2, '2020-07-10'),
    (5103, 2095, 4384, 3070, 3, '2022-04-02'),
    (5074, 2409, 4405, 3904, 5, '2019-08-06'),
    (5605, 2984, 4535, 3577, 9.2, '2020-01-02'),
    (5306, 2322, 4689, 3907, 4.5, '2022-05-03'),
    (5047, 2030, 4787, 3347, 4.5, '2021-02-18'),
    (5708, 2146, 4844, 3502, 2, '2023-03-30'),
    (5109, 2036, 4989, 3313, 1.9, '2023-08-20'),
    (5010, 2065, 4105, 3914, 9.7, '2020-04-23'),
    (5141, 2132, 4111, 3265, 9, '2022-07-18'),
    (5182, 2275, 4126, 3342, 8, '2021-08-14'),
    (5173, 2368, 4139, 3515, 3, '2019-03-22'),
    (5414, 2402, 4147, 3546, 3.4, '2018-12-31'),
    (5455, 2568, 4155, 3742, 4.1, '2022-02-13'),
    (5666, 2674, 4169, 3958, 6.6, '2020-05-06'),
    (5947, 2734, 4174, 3249, 8.7, '2023-02-11'),
    (5018, 2885, 4180, 3514, 2, '2021-03-08'),
    (5859, 2903, 4191, 3361, 4, '2020-10-07'),
    (5030, 2009, 4202, 3242, 6, '2022-12-22'),
    (5887, 2287, 4202, 3242, 3, '2022-10-04'),
    (5888, 2288, 4202, 3242, 8, '2022-10-14'),
    (5889, 2289, 4202, 3242, 9, '2022-10-24');
    

INSERT INTO visits (visit_ID, appointment_id, outcome)
VALUES
    (9001, 6611, 'Y'), 
    (9002, 6012, 'N'),  
    (9003, 6653, 'Waiting'), 
    (9004, 6324, 'Y'),  
    (9005, 6645, 'N'),  
    (9006, 6056, 'Waiting'),  
    (9007, 6857, 'Y'),  
    (9008, 6238, 'N'),  
    (9009, 6809, 'Waiting'),  
    (9010, 6610, 'Y');  


INSERT INTO reviews(review_ID, property_ID, client_ID, rating_property, review_comment, date_review)
VALUES  
    (10851, 2651, 4651, 4, 'Beautiful house with a scenic view!', '2019-05-11'),
    (10713, 2736, 4221, 3, 'The apartment was decent.', '2020-07-12'),
    (10835, 2095, 4384, 5, 'Loved the condominium and its facilities.', '2022-04-18'),
    (10445, 2409, 4405, 4, 'Great house, spacious and well-maintained.', '2019-09-09'),
    (10528, 2984, 4535, 5, 'Excellent duplex layout!', '2020-01-03'),
    (10485, 2322, 4126, 3, 'House needs some repairs, but overall okay.', '2022-11-09'),
    (10745, 2030, 4202, 4, 'Duplex suited our needs perfectly.', '2021-10-11'),
    (10384, 2146, 4174, 5, 'The villa was amazing, great location!', '2023-04-13'),
    (10968, 2036, 4989, 4, 'Good experience, the property was as described.', '2023-08-31'),
    (10630, 2065, 4105, 3, 'Industrial property needs some renovations.', '2020-05-05');

######### QUERIES ########

/* 1 - List all the customer’s names, dates, and products or services used/booked/rented/bought by
these customers in a range of two dates. */ 
SELECT
    clients.first_name as customer_first_name,
    clients.last_name as customer_last_name,
    transactions.date_transaction as transaction_date,
    properties.property_TYPE as product_or_service
FROM
    clients
JOIN
    transactions on clients.client_ID = transactions.client_ID
JOIN
    properties on transactions.property_ID = properties.property_ID
WHERE
    transactions.date_transaction between '2021-01-01' and '2021-12-31';
    
/* 2 - List the best three customers/products/services/places (you are free to define the criteria for
what means “best”). In our case: list the customers that have spend the most. */ 

SELECT
    c.client_ID,
    c.first_name,
    c.last_name,
    SUM(p.listing_price) as total_spent
FROM
    clients c
JOIN
    transactions t on c.client_ID = t.client_ID
JOIN
    properties p on t.property_ID = p.property_ID
GROUP BY
    c.client_ID, c.first_name, c.last_name
ORDER BY
    total_spent DESC
LIMIT 3;

/* 3 - Get the average amount of sales/bookings/rents/deliveries for a period that involves 2 or more
years, as in the following example. This query only returns one record. */ 

# Calculate total sales for each year
SELECT
    CONCAT(DATE_FORMAT(MIN(date_transaction), '%m/%Y'), ' – ', DATE_FORMAT(MAX(date_transaction), '%m/%Y')) AS PeriodOfSales,
    SUM(listing_price) AS TotalSales,
    SUM(listing_price) / (TIMESTAMPDIFF(YEAR, MIN(date_transaction), MAX(date_transaction)) + 1) AS YearlyAverage,
    SUM(listing_price) / (TIMESTAMPDIFF(MONTH, MIN(date_transaction), MAX(date_transaction)) + 1) AS MonthlyAverage
FROM
    transactions
    JOIN properties ON transactions.property_ID = properties.property_ID
WHERE
    date_transaction >= '2019-01-01' AND date_transaction < '2021-01-01';
/* 4 - Get the total sales/bookings/rents/deliveries by geographical location (city/country). */
# assuming the 'address' column represents cities
# Calculate total sales for each year
SELECT
    p.city as location,
    SUM(p.listing_price) as total_sales
FROM
    transactions t
JOIN
    properties p on t.property_ID = p.property_ID
GROUP BY
    p.city;

/* 5 - List all the locations where products/services were sold, and the product has customer’s ratings
(Yes, your ERD must consider that customers can give ratings). */
SELECT distinct
    p.city as location
FROM
    transactions t
JOIN
    properties p on t.property_ID = p.property_ID
JOIN
    reviews r on t.property_ID = r.property_ID
WHERE
    t.review_process IS NOT NULL;
    

############### VIEWS #################
##1 
-- This View is the Invoice's Head and Totals
-- We decided to represent the purchases of customer 4202 for the real state company 'Silver Oak Estates'
DROP VIEW IF EXISTS silverproperties_sales_to_cust4202;
CREATE VIEW silverproperties_sales_to_cust4202 AS
SELECT
    'Silver Oak Estates' AS Company,
    CURRENT_DATE AS Date,
    FLOOR(RAND() * 100000) AS "Invoice Number",
    CONCAT(c.first_name, ' ', c.last_name) AS "Customer Name",
    COALESCE(SUM(p.listing_price), 0) AS "Total Sales"
FROM
    companies comp
JOIN contracts_owner co ON comp.company_ID = co.company_ID
JOIN properties p ON co.property_ID = p.property_ID
LEFT JOIN transactions t ON p.property_ID = t.property_ID
LEFT JOIN clients c ON t.client_ID = c.client_ID
WHERE
    comp.comp_name = 'Silver Oak Estates'
    AND (p.prop_status = 'Sold')
    AND c.client_ID = 4202
GROUP BY
    comp.comp_name, c.first_name, c.last_name;

SELECT * FROM silverproperties_sales_to_cust4202;
    
##2
-- This View gives us the properties bought and some of its detais 
-- We used the same company and customer as the views are part of the same invoice
DROP VIEW IF EXISTS invoice_details_for_cust4202;
CREATE VIEW invoice_details_for_cust4202 AS
SELECT
    t.transaction_ID AS Transaction,
    p.property_ID AS "Property ID",
    p.property_TYPE AS Type,
    p.listing_price AS Price,
    CONCAT(a.first_name_agent, ' ', a.last_name_agent) AS Agent
FROM
    transactions t
JOIN properties p ON t.property_ID = p.property_ID
JOIN agents a ON t.agent_ID = a.agent_ID
JOIN contracts_owner co ON t.property_ID = co.property_ID
WHERE
    t.client_ID = 4202
    AND co.company_ID = (SELECT company_ID 
    FROM companies 
    WHERE comp_name = 'Silver Oak Estates');

SELECT * FROM invoice_details_for_cust4202;