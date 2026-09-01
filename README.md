# Hospital Readmission Risk Analysis

SQL-based analysis of 69,198 hospital encounters from the UCI Diabetes 130-US Hospitals dataset, exploring which patients are most likely to be readmitted within 30 days, and why.

## Business Question

Which patients are most likely to bounce back within 30 days of discharge, and what factors are driving that risk? The goal is to identify patterns a hospital could act on, not just describe the data, but point toward where intervention would matter most.

## Data Source

- **Dataset:** UCI Machine Learning Repository — Diabetes 130-US Hospitals for Years 1999-2008
- **Raw size:** 100,000+ encounters across 130 US hospitals
- **Scope after cleaning:** 69,198 unique patients (first encounter only, hospice/expired patients excluded — see Known Limitations)

## Tools & Techniques

- **MySQL / MySQL Workbench**
- Data cleaning: `NULLIF()` standardization, column type correction, missing-data audits
- Deduplication via self-join on `MIN(encounter_id)` per patient
- CTEs (Common Table Expressions)
- Window functions: `RANK() OVER (PARTITION BY ...)`, `NTILE()`
- Correlated subqueries (`HAVING` clause comparisons against population averages)
- `CASE` statement feature engineering (risk flags, diagnosis categorization, age bucketing)

## Methodology

1. Cleaned raw data: standardized `?` placeholders to `NULL`, corrected a column type causing truncation on diagnosis codes.
2. Audited missingness — dropped `weight` (96.9% missing), kept `payer_code` and `medical_specialty` despite partial missingness.
3. Deduplicated to one encounter per patient (first encounter only) to avoid frequently-hospitalized patients skewing results.
4. Excluded hospice/expired patients, since they cannot be "readmitted."
5. Built clean lookup tables (`discharge_disposition_map`, `admission_source_map`) to replace a combined reference table that mixed multiple unrelated code categories together.
6. Engineered features: binary readmission flag, numeric age midpoint, diagnosis category buckets from ICD-9 code ranges.
7. Ran exploratory + risk-segmentation queries using CTEs and window functions.

## Key Findings

**Baseline:** Of 69,198 patients, 59.3% were not readmitted, 31.7% were readmitted after 30 days, and 9.0% were readmitted within 30 days (the primary metric of interest throughout this analysis).

**1. Discharge disposition is the strongest predictor of readmission risk.**
Patients discharged to a rehabilitation facility were readmitted at **27.7%**, nearly 4x the rate of patients discharged straight home (**6.9%**). Risk scales with how much ongoing care a patient needed at discharge:


**2. Diagnosis category matters — but not the way you'd expect.**
Among diagnosis categories, Injury (11.0%), Circulatory disease (9.7%), and Diabetes itself (9.2%) all exceeded the population average readmission rate. Notably, in a dataset built entirely around diabetic encounters, diabetes ranked *third*, behind injury and circulatory conditions, suggesting comorbidities may drive readmission risk more than the diabetes diagnosis alone.

**3. A1C testing correlates with better outcomes, regardless of the result.**
Patients who were **not** tested for A1C during their stay had a *higher* readmission rate (9.1%) than patients who were tested, regardless of whether the result came back normal or elevated (8.2%–8.6%). This suggests the act of testing — and the care engagement it reflects — may matter more than the severity of the result itself, consistent with published clinical research behind this dataset.

**4. Age trends upward through mid-to-late adulthood.**
Readmission rate climbs steadily from the 40s through the 80s/90s age brackets, even as raw patient volume peaks earlier (around age 70-80) and then declines, meaning rate and volume follow independent patterns.

## Known Limitations

This project was completed under a tight timeline, and two data-integrity issues were identified during analysis but intentionally left unresolved. Both are documented here and directly in code comments for transparency:

The hospice/expired patient exclusion list included one incorrect code.** The exclusion codes were sourced from the same combined lookup table, and code 26 (which means "Transfer from Hospice" in the admission source category) was mistakenly included alongside the correct discharge-disposition hospice/expired codes, which also uses 26 to mean "Unknown/Invalid." This means some "Unknown/Invalid" discharge patients were incorrectly excluded from the dataset. **Fix:** rebuild `diabetic_data_dedup` using the corrected exclusion list (11, 13, 14, 19, 20, 21 only).

## Files

- `Hospital_Readmission_Risk_Analysis.sql` — full annotated SQL script, cleaning through analysis
