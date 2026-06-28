-- ============================================================
-- PROJECT   : FinEdge Lending — Credit Risk SQL Analysis
-- DATASET   : credit_risk_dataset.csv (32,581 rows, 12 columns)
-- TOOL      : DB Browser for SQLite
-- AUTHOR    : [Your Name]
-- PURPOSE   : End-to-end SQL analysis covering data cleaning,
--             feature engineering, risk reporting, and
--             strategic lending policy recommendations.
--
-- PIPELINE OVERVIEW (The Sequence That Matters):
--   RAW loans table
--     → STEP 1 : Explore (profile the data before touching it)
--     → STEP 2 : Remove duplicates (structural issue first)
--     → STEP 3 : Filter outliers (single-column impossibilities)
--     → STEP 4 : Cross-field validation (multi-column logic)
--     → STEP 5 : Impute missing values (on already-clean data)
--     → STEP 6 : Feature engineering (derived columns/ratios)
--     → STEP 7 : Business analysis (risk, strategy, insights)
-- ============================================================


-- ============================================================
-- STEP 1 : INITIAL DATA EXPLORATION
-- Goal   : Understand the raw data BEFORE modifying anything.
--          Blind cleaning leads to wrong decisions.
-- ============================================================

-- 1a. Basic row count and impossible range check
--     This single query reveals the two critical data quality
--     issues that will drive our entire cleaning strategy:
--     person_age max = 144 (impossible), emp_length max = 123.
SELECT
    COUNT(*)                      AS total_rows,
    MIN(person_age)               AS min_age,
    MAX(person_age)               AS max_age,
    MIN(person_emp_length)        AS min_emp_length,
    MAX(person_emp_length)        AS max_emp_length,
    MIN(person_income)            AS min_income,
    MAX(person_income)            AS max_income,
    MIN(loan_amnt)                AS min_loan,
    MAX(loan_amnt)                AS max_loan,
    MIN(loan_int_rate)            AS min_rate,
    MAX(loan_int_rate)            AS max_rate
FROM loans;

-- 1b. Null / missing value count per column
--     SQLite does not have a single-command null summary,
--     so we count nulls for the two columns known to have them.
SELECT
    SUM(CASE WHEN loan_int_rate     IS NULL THEN 1 ELSE 0 END) AS null_interest_rate,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS null_emp_length,
    SUM(CASE WHEN person_age        IS NULL THEN 1 ELSE 0 END) AS null_age,
    SUM(CASE WHEN person_income     IS NULL THEN 1 ELSE 0 END) AS null_income
FROM loans;
-- Expected findings: ~3,116 nulls in loan_int_rate, ~895 in person_emp_length

-- 1c. Categorical field integrity check
--     Ensures no hidden typos (e.g. 'Rent' vs 'RENT') that
--     would cause GROUP BY to split one category into two.
SELECT person_home_ownership, COUNT(*) AS count FROM loans GROUP BY 1;
SELECT loan_grade,            COUNT(*) AS count FROM loans GROUP BY 1 ORDER BY 1;
SELECT loan_intent,           COUNT(*) AS count FROM loans GROUP BY 1;
SELECT cb_person_default_on_file, COUNT(*) AS count FROM loans GROUP BY 1;

-- 1d. Overall baseline default rate
--     loan_status = 1 means defaulted, 0 means healthy.
--     AVG on a 0/1 column directly gives the default rate.
SELECT
    COUNT(*)                              AS total_loans,
    SUM(loan_status)                      AS total_defaults,
    ROUND(AVG(loan_status) * 100, 2)      AS overall_default_rate_pct
FROM loans;
-- Baseline: ~21.8% default rate — well above a healthy <5% NPA benchmark.


-- ============================================================
-- STEP 2 : DUPLICATE DETECTION & REMOVAL
-- Goal   : Remove exact row duplicates that artificially
--          inflate loan volumes and risk frequencies.
--
-- IMPORTANT: Detection uses only key columns (useful for
-- spotting patterns), but removal uses SELECT DISTINCT *
-- which checks ALL 12 columns — this is correct behaviour.
-- ============================================================

-- 2a. Detect duplicate patterns (key-column check)
--     Shows which combination of attributes repeats most.
SELECT
    person_age, person_income, person_home_ownership,
    loan_intent, loan_amnt, loan_grade, loan_status,
    COUNT(*) AS duplicate_count
FROM loans
GROUP BY 1, 2, 3, 4, 5, 6, 7
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 2b. Confirm exact-row duplicate count (all 12 columns)
SELECT
    COUNT(*)                                      AS raw_total,
    (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM loans)) AS unique_total,
    COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM loans)) AS duplicates_to_remove
FROM loans;
-- Expected: 165 exact duplicates

-- 2c. Create the deduplicated base table
--     This becomes the single source for ALL subsequent steps.
--     Using a table (not a CTE) so every downstream view
--     builds from confirmed-clean data.
DROP TABLE IF EXISTS deduped_loans;
CREATE TABLE deduped_loans AS
SELECT DISTINCT * FROM loans;

-- 2d. Verify
SELECT COUNT(*) AS post_dedup_count FROM deduped_loans;
-- Expected: 32,416


-- ============================================================
-- STEP 3 : SINGLE-COLUMN OUTLIER FILTERING
-- Goal   : Remove records with values that are physically or
--          biologically impossible, regardless of other columns.
--
-- Business cutoffs chosen:
--   person_age     <= 100  (144-year-old cannot hold a loan)
--   person_emp_length <= 60 (bounded by working lifetime)
--   person_income  <= 1,000,000 (extreme outlier: $6M income
--                   in a dataset with 75th pct = $79K skews
--                   all income-based calculations)
--
-- NULL HANDLING: OR IS NULL preserves rows with missing values
-- so they are NOT silently removed here — they will be
-- handled in Step 5 (imputation).
-- ============================================================

-- 3a. Count records that will be removed per column
SELECT
    SUM(CASE WHEN person_age > 100         THEN 1 ELSE 0 END) AS age_outliers,
    SUM(CASE WHEN person_emp_length > 60   THEN 1 ELSE 0 END) AS emp_outliers,
    SUM(CASE WHEN person_income > 1000000  THEN 1 ELSE 0 END) AS income_outliers
FROM deduped_loans;
-- Expected: 5, 2, 9 — all tiny fractions (<0.05% each)

-- 3b. Apply outlier filter
--     Parentheses around each OR-IS NULL pair are CRITICAL.
--     Without them, SQL operator precedence (AND before OR)
--     silently produces wrong results — rows that should be
--     kept get dropped, and rows that should be dropped stay.
DROP VIEW IF EXISTS v_outlier_filtered;
CREATE VIEW v_outlier_filtered AS
SELECT *
FROM deduped_loans
WHERE (person_age        <= 100       OR person_age        IS NULL)
  AND (person_emp_length <= 60        OR person_emp_length IS NULL)
  AND (person_income     <= 1000000   OR person_income     IS NULL);

SELECT COUNT(*) AS post_outlier_count FROM v_outlier_filtered;
-- Expected: ~32,401


-- ============================================================
-- STEP 4 : CROSS-FIELD LOGICAL VALIDATION
-- Goal   : Remove records where two columns together form an
--          impossible combination, even if each column looks
--          valid individually.
--
-- Rule applied:
--   (person_age - person_emp_length) must be >= 16
--   Rationale: minimum legal working age is ~16. A 22-year-old
--   with 20 years of experience is impossible regardless of
--   whether 22 and 20 individually pass the outlier filters.
--
-- Why >= 16 and not just age > emp_length?
--   age > emp_length only checks that emp_length is shorter
--   than age. A 20-year-old with 19 years employment would
--   pass (20 > 19 = TRUE) but is clearly impossible.
--   The buffer of 16 ensures we catch these edge cases.
-- ============================================================

-- 4a. Check how many records violate the age-employment rule
SELECT COUNT(*) AS invalid_age_emp_combinations
FROM v_outlier_filtered
WHERE (person_age - person_emp_length) < 16;

-- 4b. Inspect the actual violations before removing
SELECT person_age, person_emp_length,
       (person_age - person_emp_length) AS implied_start_age
FROM v_outlier_filtered
WHERE (person_age - person_emp_length) < 16
ORDER BY implied_start_age;

-- 4c. Math validation: does loan_percent_income match calculation?
--     Flags records where the provided ratio deviates >1%
--     from what loan_amnt / person_income produces.
--     A small number of mismatches may indicate the original
--     column used a different base (e.g. monthly income).
SELECT
    COUNT(*) AS mismatched_loan_pct_rows,
    ROUND(AVG(ABS((loan_amnt * 1.0 / person_income) - loan_percent_income)), 4) AS avg_deviation
FROM v_outlier_filtered
WHERE ABS((loan_amnt * 1.0 / person_income) - loan_percent_income) > 0.01;

-- 4d. Apply the cross-field logical filter
DROP VIEW IF EXISTS v_logically_valid;
CREATE VIEW v_logically_valid AS
SELECT *
FROM v_outlier_filtered
WHERE (person_age - person_emp_length) >= 16;

SELECT COUNT(*) AS post_logic_filter_count FROM v_logically_valid;


-- ============================================================
-- STEP 5 : MISSING VALUE IMPUTATION
-- Goal   : Fill remaining NULLs using group-wise statistics
--          calculated on the ALREADY CLEAN data (Steps 2-4).
--          Imputing before cleaning would distort the medians
--          with garbage values like age=144 or income=$6M.
--
-- Strategy:
--   loan_int_rate  → grade-wise AVG (rates are grade-driven)
--   person_emp_length → overall median proxy (4.0 years)
--     Note: Using a fixed median here because SQLite does not
--     have a native MEDIAN() function. In PostgreSQL/BigQuery
--     PERCENTILE_CONT(0.5) WITHIN GROUP would be preferred.
-- ============================================================

-- 5a. Confirm nulls remaining after Steps 2-4
SELECT
    SUM(CASE WHEN loan_int_rate     IS NULL THEN 1 ELSE 0 END) AS null_rates,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS null_emp
FROM v_logically_valid;

-- 5b. Preview grade-wise average rates (used for imputation)
SELECT
    loan_grade,
    ROUND(AVG(loan_int_rate), 3) AS grade_avg_rate,
    COUNT(*)                     AS total_records,
    SUM(CASE WHEN loan_int_rate IS NULL THEN 1 ELSE 0 END) AS null_count
FROM v_logically_valid
GROUP BY loan_grade
ORDER BY loan_grade;

-- 5c. Create the final cleaned table with imputation applied
DROP TABLE IF EXISTS cleaned_credit_risk;
CREATE TABLE cleaned_credit_risk AS
SELECT
    person_age,
    person_income,
    person_home_ownership,
    -- Employment length: fill NULLs with dataset median (4.0)
    -- Using 4.0 rather than 0 to avoid creating false "never worked"
    -- signals in downstream stability ratios.
    COALESCE(
        person_emp_length,
        4.0
    ) AS person_emp_length,
    loan_intent,
    loan_grade,
    loan_amnt,
    -- Interest rate: fill NULLs with the average rate for
    -- that specific loan grade (grade is the primary rate driver).
    COALESCE(
        loan_int_rate,
        AVG(loan_int_rate) OVER (PARTITION BY loan_grade)
    ) AS loan_int_rate,
    loan_status,
    loan_percent_income,
    cb_person_default_on_file,
    cb_person_cred_hist_length
FROM v_logically_valid;

-- 5d. Confirm zero nulls in the final table
SELECT
    SUM(CASE WHEN loan_int_rate     IS NULL THEN 1 ELSE 0 END) AS remaining_null_rates,
    SUM(CASE WHEN person_emp_length IS NULL THEN 1 ELSE 0 END) AS remaining_null_emp,
    MAX(person_age)                                             AS final_max_age,
    MAX(person_emp_length)                                      AS final_max_emp,
    MAX(person_income)                                          AS final_max_income,
    COUNT(*)                                                    AS final_row_count
FROM cleaned_credit_risk;


-- ============================================================
-- STEP 6 : DATA QUALITY AUDIT REPORT
-- Goal   : Produce a single, honest attrition log that a
--          stakeholder can read to understand exactly how
--          many rows were removed at each stage and why.
--          All counts come from the SAME pipeline so numbers
--          are internally consistent.
-- ============================================================

SELECT 'Stage'                          AS pipeline_stage,
       'Row Count'                      AS row_count,
       'Rows Removed'                   AS rows_removed,
       'Reason'                         AS reason
UNION ALL
SELECT '1. Raw Data',
       CAST(COUNT(*) AS TEXT),
       '—',
       'Source file as loaded'
FROM loans
UNION ALL
SELECT '2. After Duplicate Removal',
       CAST(COUNT(*) AS TEXT),
       CAST((SELECT COUNT(*) FROM loans) - COUNT(*) AS TEXT),
       'Exact row duplicates removed (all 12 columns matched)'
FROM deduped_loans
UNION ALL
SELECT '3. After Outlier Filtering',
       CAST(COUNT(*) AS TEXT),
       CAST((SELECT COUNT(*) FROM deduped_loans) - COUNT(*) AS TEXT),
       'age>100, emp_length>60, income>1M removed'
FROM v_outlier_filtered
UNION ALL
SELECT '4. After Cross-Field Validation',
       CAST(COUNT(*) AS TEXT),
       CAST((SELECT COUNT(*) FROM v_outlier_filtered) - COUNT(*) AS TEXT),
       'Records where (age - emp_length) < 16 removed'
FROM v_logically_valid
UNION ALL
SELECT '5. Final Analysis-Ready Table',
       CAST(COUNT(*) AS TEXT),
       '0',
       'NULLs imputed — no rows removed in this step'
FROM cleaned_credit_risk;


-- ============================================================
-- STEP 7 : FEATURE ENGINEERING
-- Goal   : Add business-meaningful derived columns to the
--          cleaned table. These power ALL downstream analysis.
-- ============================================================

DROP TABLE IF EXISTS foundation_credit_risk;
CREATE TABLE foundation_credit_risk AS
SELECT
    *,

    -- 7a. Age Tier
    --     Segments applicants into career-stage buckets.
    --     Useful for demographic risk heatmaps.
    CASE
        WHEN person_age BETWEEN 20 AND 25 THEN '20-25 (Entry Level)'
        WHEN person_age BETWEEN 26 AND 35 THEN '26-35 (Mid-Career)'
        WHEN person_age BETWEEN 36 AND 50 THEN '36-50 (Established)'
        ELSE '51+ (Senior)'
    END AS age_tier,

    -- 7b. Income Bracket
    --     Based on dataset distribution: 75th pct ~$79K.
    --     $50K and $100K are natural split points observed
    --     in the describe() output.
    CASE
        WHEN person_income < 50000              THEN 'Low Income (<50K)'
        WHEN person_income BETWEEN 50000 AND 100000 THEN 'Medium Income (50-100K)'
        ELSE                                         'High Income (100K+)'
    END AS income_bracket,

    -- 7c. Behavioural Risk Segment
    --     Combines credit FILE history with CURRENT loan status
    --     to create four meaningful risk labels.
    --     "Repeat Default" = filed default before AND defaulted now.
    --     "Warning" = historical default but currently performing.
    --     "New Default" = first-time default (no prior record).
    --     "Stable" = clean record, performing loan.
    CASE
        WHEN cb_person_default_on_file = 'Y' AND loan_status = 1
            THEN 'High Risk (Repeat Default)'
        WHEN cb_person_default_on_file = 'Y' AND loan_status = 0
            THEN 'Warning (Historical Default, Currently Performing)'
        WHEN cb_person_default_on_file = 'N' AND loan_status = 1
            THEN 'New Default (First-Time)'
        ELSE
            'Stable'
    END AS risk_segment,

    -- 7d. Work-Life Ratio (Stability Index)
    --     What fraction of the applicant's life has been
    --     spent in employment? Higher = more financially stable.
    --     Formula: emp_length / age
    ROUND(CAST(person_emp_length AS REAL) / person_age, 3)
        AS work_life_ratio,

    -- 7e. Interest Burden Ratio (Financial Strain Index)
    --     How much of annual income will be consumed by
    --     interest payments alone?
    --     Formula: (loan_amnt * annual_rate) / income
    ROUND((loan_amnt * (loan_int_rate / 100.0)) / person_income, 4)
        AS interest_burden_ratio,

    -- 7f. Calculated Loan Weight (Debt-to-Income Check)
    --     Independent recalculation of loan_percent_income
    --     to verify the provided column's accuracy.
    ROUND(CAST(loan_amnt AS REAL) / person_income, 3)
        AS calculated_loan_weight,

    -- 7g. Credit History Tier
    --     Buckets credit history length for the Credit Tenure
    --     Paradox analysis (Section 9).
    CASE
        WHEN cb_person_cred_hist_length <= 2             THEN 'New Credit (0-2y)'
        WHEN cb_person_cred_hist_length BETWEEN 3 AND 5  THEN 'Established (3-5y)'
        WHEN cb_person_cred_hist_length BETWEEN 6 AND 10 THEN 'Experienced (6-10y)'
        ELSE                                              'Veteran (10y+)'
    END AS credit_tenure_tier

FROM cleaned_credit_risk;

SELECT COUNT(*) AS foundation_row_count FROM foundation_credit_risk;


-- ============================================================
-- SECTION 8 : CORE RISK ANALYSIS
-- ============================================================

-- 8a. Default Rate by Loan Grade
--     The most fundamental risk segmentation in the portfolio.
--     Confirms the grade-to-rate pricing model works directionally
--     but Grade D-G are charging too little for the actual risk.
SELECT
    loan_grade,
    COUNT(*)                            AS total_loans,
    SUM(loan_status)                    AS total_defaults,
    ROUND(AVG(loan_status) * 100, 2)    AS default_rate_pct,
    ROUND(AVG(loan_amnt), 0)            AS avg_loan_amount,
    ROUND(AVG(loan_int_rate), 2)        AS avg_interest_rate,
    ROUND(AVG(work_life_ratio), 3)      AS avg_stability,
    ROUND(AVG(interest_burden_ratio), 4) AS avg_burden
FROM foundation_credit_risk
GROUP BY loan_grade
ORDER BY loan_grade;

-- 8b. Portfolio-at-Risk by Grade (Dollar Impact)
--     Default rate alone does not tell the full story.
--     A grade with 59% default rate AND high volume is far
--     more dangerous than 98% default on 64 loans.
--     This query converts % risk into dollar exposure.
WITH grade_risk AS (
    SELECT
        loan_grade,
        COUNT(*)                            AS total_loans,
        ROUND(AVG(loan_status) * 100, 1)    AS default_rate_pct,
        ROUND(AVG(loan_amnt), 0)            AS avg_loan_amount,
        ROUND(COUNT(*) * AVG(loan_amnt) / 1000000.0, 2) AS total_portfolio_mn
    FROM foundation_credit_risk
    GROUP BY loan_grade
),
high_risk AS (
    SELECT *
    FROM grade_risk
    WHERE default_rate_pct > 25
)
SELECT
    h.*,
    ROUND(h.total_portfolio_mn * h.default_rate_pct / 100, 2) AS portfolio_at_risk_mn
FROM high_risk h
ORDER BY portfolio_at_risk_mn DESC;
-- Key insight: Grade D has ~59% default rate but HIGHEST dollar exposure
-- because it has the most volume. Focus risk mitigation on Grade D first.

-- 8c. Overall Revenue Leakage Estimate
--     Worst-case (zero recovery) estimate of revenue lost
--     due to defaults: principal + 3-year interest income.
SELECT
    COUNT(*)                                                AS defaulted_loans,
    ROUND(SUM(loan_amnt) / 1000000.0, 2)                   AS principal_at_risk_mn,
    ROUND(SUM(loan_amnt * loan_int_rate / 100.0 * 3) / 1000000.0, 2)
                                                            AS interest_income_lost_mn,
    ROUND((SUM(loan_amnt) +
           SUM(loan_amnt * loan_int_rate / 100.0 * 3)) / 1000000.0, 2)
                                                            AS total_revenue_leakage_mn
FROM foundation_credit_risk
WHERE loan_status = 1;
-- Note: This is an upper-bound estimate assuming zero recovery.
-- Real loss is lower due to partial collections and collateral.

-- 8d. Default Rate by Home Ownership
--     Tests whether housing stability predicts repayment behaviour.
SELECT
    person_home_ownership,
    COUNT(*)                            AS total_loans,
    ROUND(AVG(loan_status) * 100, 2)    AS default_rate_pct,
    ROUND(AVG(person_income), 0)        AS avg_income
FROM foundation_credit_risk
GROUP BY person_home_ownership
ORDER BY default_rate_pct DESC;

-- 8e. Loan-to-Income Ratio Threshold Analysis (The Cliff Effect)
--     Tests whether there is a non-linear "break point" in DTI
--     where default risk jumps sharply rather than gradually.
SELECT
    CASE
        WHEN loan_percent_income < 0.10 THEN '1 (<10%)'
        WHEN loan_percent_income < 0.20 THEN '2 (10-20%)'
        WHEN loan_percent_income < 0.30 THEN '3 (20-30%)'
        WHEN loan_percent_income < 0.40 THEN '4 (30-40%)'
        ELSE                                 '5 (40%+)'
    END AS ltir_bucket,
    COUNT(*)                            AS total_loans,
    ROUND(AVG(loan_status) * 100, 2)    AS default_rate_pct
FROM foundation_credit_risk
GROUP BY ltir_bucket
ORDER BY ltir_bucket;
-- Key finding: Rate goes 12% → 15% → 22% → 69% → 74%
-- The 30% threshold is a cliff point: risk triples crossing it.
-- Recommendation: Hard DTI cap at 30% in underwriting policy.


-- ============================================================
-- SECTION 9 : ADVANCED WINDOW FUNCTION ANALYSIS
-- ============================================================

-- 9a. Running cumulative default count by grade (A through G)
--     Shows what % of the total default problem is concentrated
--     in the first few grades when viewed cumulatively.
SELECT
    loan_grade,
    COUNT(*)                                    AS loans_in_grade,
    SUM(loan_status)                            AS defaults_in_grade,
    SUM(SUM(loan_status)) OVER (
        ORDER BY loan_grade
    )                                           AS running_total_defaults,
    ROUND(AVG(loan_status) * 100, 2)            AS grade_default_rate_pct
FROM foundation_credit_risk
GROUP BY loan_grade
ORDER BY loan_grade;

-- 9b. Rank loans within each grade by loan amount
--     Useful for identifying the highest-exposure defaulted
--     loans inside each risk tier.
SELECT
    loan_grade,
    loan_amnt,
    loan_status,
    loan_int_rate,
    ROW_NUMBER() OVER (
        PARTITION BY loan_grade
        ORDER BY loan_amnt DESC
    ) AS rank_within_grade
FROM foundation_credit_risk
LIMIT 50;
-- ROW_NUMBER used (not RANK) to guarantee unique row identifiers
-- even when loan amounts are tied at the same value.

-- 9c. Grade-level default rate vs overall average (Subquery)
--     Identifies which grades are performing worse than the
--     portfolio average — using a DYNAMIC threshold so this
--     query remains accurate even if new data is loaded.
SELECT
    loan_grade,
    ROUND(AVG(loan_status) * 100, 2)                            AS grade_default_rate_pct,
    ROUND((SELECT AVG(loan_status) FROM foundation_credit_risk) * 100, 2)
                                                                AS overall_avg_rate_pct
FROM foundation_credit_risk
GROUP BY loan_grade
HAVING AVG(loan_status) > (SELECT AVG(loan_status) FROM foundation_credit_risk)
ORDER BY grade_default_rate_pct DESC;
-- Dynamic subquery: threshold auto-updates if dataset changes.
-- No hardcoded "25%" — future-proof design.


-- ============================================================
-- SECTION 10 : STRATEGIC RISK DEEP DIVE
-- ============================================================

-- 10a. Loan Intent vs Default Rate
--      Tests whether the purpose of the loan is a meaningful
--      predictor of repayment behaviour.
SELECT
    loan_intent,
    COUNT(*)                                AS total_loans,
    ROUND(AVG(loan_status) * 100, 2)        AS default_rate_pct,
    ROUND(AVG(interest_burden_ratio), 4)    AS avg_burden
FROM foundation_credit_risk
GROUP BY loan_intent
ORDER BY default_rate_pct DESC;
-- Finding: Debt Consolidation + Medical are "Stress Zone" (>26% default).
-- Venture + Education are "Growth Zone" (<17% default).
-- Policy: Apply higher interest rate floor for Stress Zone intents.

-- 10b. The Credit Tenure Paradox
--      Tests the common assumption that longer credit history
--      = significantly lower risk.
SELECT
    credit_tenure_tier,
    COUNT(*)                            AS applicant_count,
    ROUND(AVG(loan_status) * 100, 2)    AS default_rate_pct
FROM foundation_credit_risk
GROUP BY credit_tenure_tier
ORDER BY default_rate_pct DESC;
-- Finding: Veteran (10y+) only 2.7% safer than New Credit (0-2y).
-- Conclusion: Credit tenure is a WEAK primary predictor.
-- Recommendation: Replace tenure weight with work_life_ratio in scoring.

-- 10c. Foundational performance: Income Bracket × Age Tier
--      Cross-dimensional view of default rates to identify
--      which demographic intersections carry the highest risk.
SELECT
    income_bracket,
    age_tier,
    COUNT(*)                            AS applicant_count,
    ROUND(AVG(loan_status) * 100, 2)    AS default_rate_pct,
    ROUND(AVG(loan_int_rate), 2)        AS avg_offered_rate
FROM foundation_credit_risk
GROUP BY income_bracket, age_tier
ORDER BY income_bracket, default_rate_pct DESC;

-- 10d. Risk Segment Distribution
--      Shows the breakdown of the four behavioural risk segments
--      engineered in Step 7.
SELECT
    risk_segment,
    COUNT(*)                            AS applicant_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM foundation_credit_risk), 2)
                                        AS pct_of_portfolio
FROM foundation_credit_risk
GROUP BY risk_segment
ORDER BY applicant_count DESC;


-- ============================================================
-- SECTION 11 : SAFE HAVEN LENDING MATRIX
-- Goal   : Identify borrower segments with near-zero default
--          probability to create a "fast-track" approval lane.
--
-- Filters applied (data-driven thresholds from Section 8):
--   work_life_ratio      > 0.20  (demonstrated career stability)
--   interest_burden_ratio < 0.03  (loan is affordable relative to income)
--   Only segments with default_rate < 5% qualify
-- ============================================================

SELECT
    income_bracket,
    age_tier,
    person_home_ownership,
    COUNT(*)                            AS qualifying_loan_count,
    ROUND(AVG(loan_status) * 100, 2)    AS default_rate_pct,
    ROUND(AVG(work_life_ratio), 3)      AS avg_stability,
    ROUND(AVG(interest_burden_ratio), 4) AS avg_burden
FROM foundation_credit_risk
WHERE work_life_ratio       > 0.20
  AND interest_burden_ratio < 0.03
GROUP BY income_bracket, age_tier, person_home_ownership
HAVING ROUND(AVG(loan_status) * 100, 2) < 5.0
ORDER BY qualifying_loan_count DESC;
-- Key insight: OWN home status is the strongest single risk hedge.
-- High and Medium Income homeowners in Mid-Career/Established tiers
-- show 0% default even when income is below average.
-- These 13+ segments should receive auto-approval or rate discounts.


-- ============================================================
-- FINAL SUMMARY : KEY FINDINGS FOR PRESENTATION
-- ============================================================

-- One-query executive summary of the portfolio
SELECT
    COUNT(*)                                     AS total_clean_loans,
    SUM(loan_status)                             AS total_defaults,
    ROUND(AVG(loan_status) * 100, 2)             AS portfolio_default_rate_pct,
    ROUND(SUM(loan_amnt) / 1000000.0, 2)         AS total_portfolio_value_mn,
    ROUND(SUM(CASE WHEN loan_status = 1
        THEN loan_amnt ELSE 0 END) / 1000000.0, 2)
                                                 AS principal_at_risk_mn,
    ROUND(AVG(loan_int_rate), 2)                 AS avg_interest_rate_pct,
    ROUND(AVG(work_life_ratio), 3)               AS avg_portfolio_stability,
    ROUND(AVG(interest_burden_ratio), 4)         AS avg_interest_burden
FROM foundation_credit_risk;

-- ============================================================
-- END OF ANALYSIS
-- Tables created : deduped_loans, cleaned_credit_risk,
--                  foundation_credit_risk
-- Views created  : v_outlier_filtered, v_logically_valid
-- Total queries  : ~40 covering exploration, cleaning,
--                  engineering, risk analysis, and strategy
-- ============================================================
