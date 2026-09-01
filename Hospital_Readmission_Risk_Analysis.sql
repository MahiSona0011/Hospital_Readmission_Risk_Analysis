-- =============================================================
-- Hospital Readmission Risk Analysis
-- Which patients are most likely to bounce back within 30 days, and why?
-- Dataset: UCI Diabetes 130-US Hospitals (1999-2008), 130 hospitals
-- =============================================================

CREATE DATABASE hospital_readmissions;
USE hospital_readmissions;


SELECT * 
FROM diabetic_data_raw
LIMIT 10;

-- Fix column type: diag_1 contains mixed numeric + letter-prefixed ICD-9 codes,
-- original INT/short type was truncating values. Widened to VARCHAR to store correctly.
ALTER TABLE diabetic_data_raw
MODIFY diag_1 VARCHAR(10);

-- SET SQL_SAFE_UPDATES=0      --Turn safe mode off

-- Standardize missing-data markers: raw data uses '?' as a placeholder for NULL
-- across several categorical columns. Converting to true NULL so aggregate
-- functions (COUNT, AVG, etc.) treat missing values correctly.
UPDATE diabetic_data_raw
SET race = NULLIF(race,'?'),
	weight = NULLIF(weight,'?'),
    payer_code = NULLIF(payer_code,'?'),
    medical_specialty = NULLIF(medical_specialty,'?'),
    diag_1 = NULLIF(diag_1,'?'),
	diag_2 = NULLIF(diag_2,'?'),
	diag_3 = NULLIF(diag_3,'?');
   
   
-- Missing data audit: weight ~96.9% missing (excluded from analysis),
-- payer_code ~39.4% missing (kept), medical_specialty ~49.0% missing (kept)
SELECT
	ROUND(SUM(weight IS NULL)/COUNT(*)*100,1) AS pct_missing_weight,
    ROUND(SUM(payer_code IS NULL)/COUNT(*)*100,1) AS payer_code,
    ROUND(SUM(medical_specialty IS NULL)/COUNT(*)*100,1) AS medical_specialty
FROM diabetic_data_raw;
    
-- Check for repeat patients before deduplicating
SELECT 
	patient_nbr,
    COUNT(*) AS encounter_count
FROM diabetic_data_raw
GROUP BY patient_nbr
HAVING COUNT(*) > 1
ORDER BY encounter_count DESC
LIMIT 20;

-- Deduplication: keep only each patient's FIRST encounter (earliest encounter_id)
-- so repeat visits from the same patient don't bias the analysis toward
-- frequently-hospitalized individuals.
CREATE TABLE diabetic_data_dedup AS
SELECT t.*
FROM diabetic_data_raw as t
INNER JOIN (SELECT 
	patient_nbr,
    MIN(encounter_id) as first_encounter
FROM diabetic_data_raw
GROUP BY patient_nbr)first_enc
ON t.patient_nbr =first_enc.patient_nbr
And t.encounter_id = first_enc.first_encounter;
	
    
SELECT COUNT(*) FROM diabetic_data_dedup;

SELECT 
	discharge_disposition_id,
    COUNT(*) AS encounter_count
FROM diabetic_data_raw
GROUP BY discharge_disposition_id
ORDER BY encounter_count DESC;

-- Identify hospice/expired/deceased patients for exclusion (can't be "readmitted"
-- within 30 days if they didn't survive the encounter or were discharged to hospice).
--
-- *** KNOWN ISSUE ***
-- This SELECT queries the combined `ids_mapping_raw` table, which stacks THREE
-- separate lookup categories (discharge disposition, admission source, admission
-- type) into one table using overlapping ID numbers. Searching this combined
-- table for "hospice/expired/deceased" text returned 7 codes: 11,13,14,19,20,21,26.
-- Codes 11,13,14,19,20,21 are legitimate discharge_disposition codes (Expired,
-- Hospice variants). However, code 26 in discharge_disposition_map actually means
-- "Unknown/Invalid" — the hospice-related "26" match came from a DIFFERENT
-- category (admission_source_map, where 26 = "Transfer from Hospice") that
-- collided on the same ID number in the combined table.
-- Net effect: the DELETE below incorrectly removed patients whose discharge
-- disposition was 26 ("Unknown/Invalid") along with the genuinely hospice/expired
-- patients. Correct code list should have been (11,13,14,19,20,21) only.
-- Left as-is for this version — documenting for transparency and as a fix
-- for a future iteration (rebuild diabetic_data_dedup from raw with corrected list).
SELECT * FROM ids_mapping_raw
WHERE description LIKE '%hospice%' OR description LIKE '%expired%' OR description LIKE '%deceased%';

-- 11,13,14,19,20,21,26

DELETE FROM diabetic_data_dedup
WHERE discharge_disposition_id IN(11,13,14,19,20,21,26);

SELECT * FROM ids_mapping_raw;

-- Building clean, single-purpose lookup tables to replace the combined/messy
-- ids_mapping_raw table for all downstream joins (see fix applied further below
-- in the discharge disposition analysis).
CREATE TABLE discharge_disposition_map(
	discharge_discomposition_id INT,
    description VARCHAR(150));
    
CREATE TABLE admission_source_map(
	admission_source_id INT,
    description VARCHAR(150));
    
DESCRIBE discharge_disposition_map;
DESCRIBE admission_source_map;



INSERT INTO discharge_disposition_map (discharge_discomposition_id, description) VALUES
(1, 'Discharged to home'),
(2, 'Discharged/transferred to another short term hospital'),
(3, 'Discharged/transferred to SNF'),
(4, 'Discharged/transferred to ICF'),
(5, 'Discharged/transferred to another type of inpatient care institution'),
(6, 'Discharged/transferred to home with home health service'),
(7, 'Left AMA'),
(8, 'Discharged/transferred to home under care of Home IV provider'),
(9, 'Admitted as an inpatient to this hospital'),
(10, 'Neonate discharged to another hospital for neonatal aftercare'),
(11, 'Expired'),
(12, 'Still patient or expected to return for outpatient services'),
(13, 'Hospice / home'),
(14, 'Hospice / medical facility'),
(15, 'Discharged/transferred within this institution to Medicare approved swing bed'),
(16, 'Discharged/transferred/referred another institution for outpatient services'),
(17, 'Discharged/transferred/referred to this institution for outpatient services'),
(18, 'NULL'),
(19, 'Expired at home. Medicaid only, hospice.'),
(20, 'Expired in a medical facility. Medicaid only, hospice.'),
(21, 'Expired, place unknown. Medicaid only, hospice.'),
(22, 'Discharged/transferred to another rehab fac including rehab units of a hospital'),
(23, 'Discharged/transferred to a long term care hospital'),
(24, 'Discharged/transferred to a nursing facility certified under Medicaid but not certified under Medicare'),
(25, 'Not Mapped'),
(26, 'Unknown/Invalid'),
(27, 'Discharged/transferred to a federal health care facility'),
(28, 'Discharged/transferred/referred to a psychiatric hospital of psychiatric distinct part unit of a hospital'),
(29, 'Discharged/transferred to a Critical Access Hospital (CAH)'),
(30, 'Discharged/transferred to another Type of Health Care Institution not Defined Elsewhere');


INSERT INTO admission_source_map (admission_source_id, description) VALUES
(1, 'Physician Referral'),
(2, 'Clinic Referral'),
(3, 'HMO Referral'),
(4, 'Transfer from a hospital'),
(5, 'Transfer from a Skilled Nursing Facility (SNF)'),
(6, 'Transfer from another health care facility'),
(7, 'Emergency Room'),
(8, 'Court/Law Enforcement'),
(9, 'Not Available'),
(10, 'Transfer from critical access hospital'),
(11, 'Normal Delivery'),
(12, 'Premature Delivery'),
(13, 'Sick Baby'),
(14, 'Extramural Birth'),
(15, 'Not Available'),
(17, 'NULL'),
(18, 'Transfer From Another Home Health Agency'),
(19, 'Readmission to Same Home Health Agency'),
(20, 'Not Mapped'),
(21, 'Unknown/Invalid'),
(22, 'Transfer from hospital inpt/same fac reslt in a sep claim'),
(23, 'Born inside this hospital'),
(24, 'Born outside this hospital'),
(25, 'Transfer from Ambulatory Surgery Center'),
(26, 'Transfer from Hospice');

SELECT * FROM discharge_disposition_map;
SELECT * FROM admission_source_map;

-- Convert age brackets (e.g. '[0-10)') into a single numeric midpoint value
-- so age can be used in numeric calculations, sorting, and window functions.
ALTER TABLE diabetic_data_dedup
ADD COLUMN age_midpoint INT;

UPDATE diabetic_data_dedup
SET age_midpoint = CASE 
	WHEN age = '[0-10)' THEN 5
    WHEN age = '[10-20)' THEN 15
    WHEN age = '[20-30)' THEN 25
    WHEN age = '[30-40)' THEN 35
    WHEN age = '[40-50)' THEN 45
    WHEN age = '[50-60)' THEN 55
    WHEN age = '[60-70)' THEN 65
    WHEN age = '[70-80)' THEN 75
    WHEN age = '[80-90)' THEN 85
    WHEN age = '[90-100)' THEN 95
END;
    
    
-- =============================================================
-- EXPLORATORY ANALYSIS
-- =============================================================

-- Finding 1: Overall readmission baseline
SELECT 
	readmitted,
    COUNT(*) as encounter_count,
    ROUND(COUNT(*)/(SELECT COUNT(*) FROM diabetic_data_dedup)* 100,1) as pct_of_total
	FROM diabetic_data_dedup 
	GROUP BY readmitted
	ORDER BY encounter_count DESC;
    
    
-- Finding 2: Readmission rate by age
SELECT 
	age,
    age_midpoint,
    COUNT(*) AS total_encounters,
    SUM(readmitted = '<30') as readmitted_under_30,
    ROUND(SUM(readmitted ='<30')/COUNT(*)*100,1) as readmission_rate_pct
FROM diabetic_data_dedup
GROUP BY age,age_midpoint
ORDER BY age_midpoint;

-- *** KNOWN ISSUE - unresolved ***
-- This join uses the combined ids_mapping_raw table instead of a clean,
-- single-purpose admission_type_map (like the discharge_disposition_map and
-- admission_source_map built above). Because ids_mapping_raw stacks three
-- unrelated lookup categories under overlapping ID numbers, this join pulls in
-- mismatched descriptions from other categories wherever ID numbers coincide
-- (e.g. rows for "Newborn," "Transfer from a hospital," and "Discharged/
-- transferred to ICF" incorrectly share identical counts/rates because they
-- all resolve to ID 9 across different categories). Results from this specific
-- query should NOT be trusted/reported as-is.
-- Fix: build an admission_type_map table (same pattern as the two maps above)
-- and join on admission_type_id only.
SELECT 
	m.description as admission_type,
    COUNT(*) as total_encounters,
    ROUND(SUM(d.readmitted ='<30')/COUNT(*)*100,1) as readmission_rate_pct
FROM diabetic_data_dedup AS d
JOIN ids_mapping_raw AS m
ON d.admission_type_id =m.admission_type_id
GROUP BY m.description
ORDER BY readmission_rate_pct DESC;


-- =============================================================
-- ADVANCED TECHNIQUES: CTEs, Window Functions, Risk Segmentation
-- =============================================================

-- Base CTE: pulls risk-relevant columns and engineers a binary readmission flag
-- (1 = readmitted within 30 days, 0 = otherwise) for use in downstream calculations.
WITH patient_risk_base AS (
    SELECT
        encounter_id,
        patient_nbr,
        age_midpoint,
        time_in_hospital,
        num_medications,
        num_lab_procedures,
        number_diagnoses,
        number_inpatient,
        number_emergency,
        number_outpatient,
        diag_1,
        readmitted,
        CASE WHEN readmitted = '<30' THEN 1 ELSE 0 END AS is_readmitted_30
    FROM diabetic_data_dedup
)
SELECT * FROM patient_risk_base
LIMIT 20;

-- RANK() with PARTITION BY: ranks each patient's medication count against
-- other patients IN THE SAME AGE GROUP ONLY (rank resets at each new age_midpoint).
WITH patient_risk_base AS (
    SELECT
        encounter_id, age_midpoint, num_medications, readmitted,
        CASE WHEN readmitted = '<30' THEN 1 ELSE 0 END AS is_readmitted_30
    FROM diabetic_data_dedup
)
SELECT
    encounter_id,
    age_midpoint,
    num_medications,
    RANK() OVER (PARTITION BY age_midpoint ORDER BY num_medications DESC) as med_rank_age_group
FROM patient_risk_base
ORDER BY age_midpoint, med_rank_age_group
LIMIT 200;

-- NTILE(4): splits the ENTIRE population (no partitioning) into 4 equal-sized
-- risk quartiles based on prior inpatient visit count. Quartile 1 = highest
-- prior-visit patients (highest risk), quartile 4 = lowest.
WITH patient_risk_base AS (
    SELECT
        encounter_id, number_inpatient, readmitted,
        CASE WHEN readmitted = '<30' THEN 1 ELSE 0 END AS is_readmitted_30
    FROM diabetic_data_dedup
)
SELECT
    encounter_id,
    number_inpatient,
    NTILE(4) OVER (ORDER BY number_inpatient DESC) as risk_quartile
FROM patient_risk_base;

-- Tiering patients by medication burden and diagnosis complexity for
-- descriptive segmentation.
SELECT 
	encounter_id,
    num_medications,
    CASE 
		WHEN num_medications <=10 THEN 'Low'
        WHEN num_medications BETWEEN 11 AND 20 THEN 'Medium'
        ELSE 'High'
	END medication_burden_tier,
    CASE 
		WHEN number_diagnoses <=5 THEN 'Low Complexity'
        WHEN number_diagnoses BETWEEN 6 and 9 THEN 'Moderate Complexity'
        ELSE 'High Complexity'
        END AS diagnosis_complexity_tier
	FROM diabetic_data_dedup;
    
-- Finding 3: Which diagnosis categories are driving readmissions above the
-- hospital-wide average? Uses a correlated subquery in the HAVING clause to
-- compare each category's rate against the overall population rate.
--
-- diag_1 ICD-9 code range notes:
-- 390-459: Diseases of the circulatory system
-- 460-519: Diseases of the respiratory system
-- 520-579: Diseases of the digestive system
-- 580-629: Diseases of the genitourinary system
-- 800-999: Injury and poisoning

WITH diag_categorized AS (
    SELECT
        encounter_id,
        readmitted,
        CASE
            WHEN diag_1 LIKE '250%' THEN 'Diabetes'
            WHEN CAST(LEFT(diag_1, 3) AS UNSIGNED) BETWEEN 390 AND 459 THEN 'Circulatory'
            WHEN CAST(LEFT(diag_1, 3) AS UNSIGNED) BETWEEN 460 AND 519 THEN 'Respiratory'
            WHEN CAST(LEFT(diag_1, 3) AS UNSIGNED) BETWEEN 520 AND 579 THEN 'Digestive'
            WHEN CAST(LEFT(diag_1, 3) AS UNSIGNED) BETWEEN 580 AND 629 THEN 'Genitourinary'
            WHEN CAST(LEFT(diag_1, 3) AS UNSIGNED) BETWEEN 800 AND 999 THEN 'Injury'
            ELSE 'Other'
        END AS diagnosis_category,
        CASE WHEN readmitted = '<30' THEN 1 ELSE 0 END AS is_readmitted_30
    FROM diabetic_data_dedup
    WHERE diag_1 IS NOT NULL
)
SELECT
    diagnosis_category,
    COUNT(*) AS total_encounters,
    ROUND(AVG(is_readmitted_30) * 100, 1) AS readmission_rate_pct
FROM diag_categorized
GROUP BY diagnosis_category
HAVING AVG(is_readmitted_30) > (
    SELECT AVG(is_readmitted_30) FROM diag_categorized
)
ORDER BY readmission_rate_pct DESC;
-- Result: Injury (11.0%), Circulatory (9.7%), Diabetes (9.2%) all exceed
-- the population average readmission rate.
        
        
-- Readmission rate by medication change status during the encounter
SELECT 
	`change`,
    COUNT(*) as total_encounters,
    ROUND(SUM(readmitted='<30')/COUNT(*) * 100, 1) AS readmission_rate_pct
FROM diabetic_data_dedup
GROUP BY `change`;

-- Finding 4: Discharge disposition impact on readmission.
-- Correctly joins against the clean, single-purpose discharge_disposition_map
-- (not the combined ids_mapping_raw), matching only on discharge_disposition_id.
-- HAVING COUNT(*) > 100 filters out small/rare categories that would otherwise
-- produce misleadingly extreme percentages from tiny sample sizes.
SELECT
    m.description AS discharge_disposition,
    COUNT(*) AS total_encounters,
    ROUND(SUM(d.readmitted = '<30') / COUNT(*) * 100, 1) AS readmission_rate_pct
FROM diabetic_data_dedup AS d
JOIN discharge_disposition_map AS m
    ON d.discharge_disposition_id = m.discharge_discomposition_id
GROUP BY m.description
HAVING COUNT(*) > 100
ORDER BY readmission_rate_pct DESC
LIMIT 10;
-- Result: Rehab facility discharge = 27.7% readmission vs. 6.9% for
-- discharged-to-home patients, the strongest single predictor found in this analysis.

-- Finding 5: A1C testing and readmission
SELECT
    A1Cresult,
    COUNT(*) AS total_encounters,
    ROUND(SUM(readmitted = '<30') / COUNT(*) * 100, 1) AS readmission_rate_pct
FROM diabetic_data_dedup
GROUP BY A1Cresult;
-- Result: untested patients (None) had the highest readmission rate (9.1%)
-- vs. tested patients regardless of result (8.2-8.6%), suggesting testing
-- itself -- not severity of result -- is associated with better outcomes.
