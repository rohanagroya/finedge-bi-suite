
SELECT * from loans LIMIT 5 ; 

-- Total rows
SELECT count(*) as Total_rows from loans;

-- Total Defaul Rate
SELECT round(avg(loan_status)*100,2) as Default_rate from loans ;

-- Analysing numbers in each grade
SELECT
	loan_grade,
	count(*) as Total_loans,
	sum(loan_status) as Default_loans,
	count(case when cb_person_default_on_file = 'Y' then 1 End) as  Default_loan_files,
	round(avg(loan_status)*100.,3) as default_rate,
	ROUND(AVG(loan_amnt), 3) as avg_loan_amount,
	ROUND(AVG(loan_int_rate), 3) as avg_loan_int,
	ROUND(AVG(loan_percent_income)*100, 3) as avg_Loan_person_income
FROM loans
GROUP by loan_grade
ORDER by loan_grade;

-- Home Ownership vs Default Rate
SELECT 
    person_home_ownership,
    COUNT(*) as total_loans,
    ROUND(AVG(loan_status)*100, 2) as default_rate_percent,
    ROUND(avg(person_income), 0) as avg_income
FROM loans
GROUP BY person_home_ownership
ORDER BY default_rate_percent DESC;

-- Range of person income=
SELECT 
	round(avg(person_income),2) as avg_income,
	min(person_income) as min_income,
	Max(person_income) as max_income
FROM loans;

-- Default by income group
SELECT
	CASE
		WHEN person_income < 30000 THEN '0k-30K'
		WHEN person_income < 60000 THEN '30k-60K'
		WHEN person_income < 90000 THEN '60k-90K'
		WHEN person_income < 1000000 THEN '90k-10L'
		WHEN person_income < 3000000 THEN '10L-30L'
		ELSE '30L-60L'
	END as Income_bucket,
	round(avg(person_income),2) as Avg_person_income,
	count(*) as total_loans,
	sum(loan_status) as Default_loans,
	round(avg(loan_status)*100,2) as Default_rate
FROM loans
GROUP by Income_bucket	
ORDER by Default_rate DESC;


SELECT 
    loan_grade,
    COUNT(*) as total_loans,
    SUM(loan_status) as defaults_in_grade,
	SUM(sum(loan_status)) OVER (ORDER by loan_grade ASC) as running_default_grade
FROM loans
GROUP BY loan_grade

		
		
SELECT
	CASE
		WHEN person_income < 30000 THEN '0k-30K'
		WHEN person_income < 60000 THEN '30k-60K'
		WHEN person_income < 90000 THEN '60k-90K'
		WHEN person_income < 1000000 THEN '90k-10L'
		WHEN person_income < 3000000 THEN '10L-30L'
		ELSE '30L-60L'
	END as Income_bucket,
	person_income,
	avg(person_income) OVER (PARTITION by CASE
		WHEN person_income < 30000 THEN '0k-30K'
		WHEN person_income < 60000 THEN '30k-60K'
		WHEN person_income < 90000 THEN '60k-90K'
		WHEN person_income < 1000000 THEN '90k-10L'
		WHEN person_income < 3000000 THEN '10L-30L'
		ELSE '30L-60L'
	END) as avg_person_income
FROM loans;


WITH Categorized_Income AS (
    SELECT 
        person_income,
        CASE
            WHEN person_income < 30000 THEN '0k-30K'
            WHEN person_income < 60000 THEN '30k-60K'
            WHEN person_income < 90000 THEN '60k-90K'
            WHEN person_income < 1000000 THEN '90k-10L'
            WHEN person_income < 3000000 THEN '10L-30L'
            ELSE '30L-60L'
        END as Income_bucket
    FROM loans
)
SELECT 
    Income_bucket,
    person_income,
    AVG(person_income) OVER (PARTITION BY Income_bucket) as avg_person_income
FROM Categorized_Income;


WITH default_rates AS (
    SELECT 
        loan_grade,
        COUNT(*) as total_loans,
        ROUND(AVG(loan_amnt), 0) as avg_loan_size,
        ROUND(AVG(loan_status)*100, 1) as default_rate
    FROM loans
    GROUP BY loan_grade
)
SELECT * FROM default_rates;


WITH default_rates AS (
    SELECT 
        loan_grade,
        COUNT(*) as total_loans,
        ROUND(AVG(loan_amnt), 0) as avg_loan_size,
        ROUND(AVG(loan_status)*100, 1) as default_rate
    FROM loans
    GROUP BY loan_grade
),
high_risk AS (
    SELECT * FROM default_rates
    WHERE default_rate > 25
)
SELECT 
    h.*,
    ROUND(h.total_loans * h.avg_loan_size / 1000000, 2) as portfolio_at_risk_mn
FROM high_risk h
ORDER BY portfolio_at_risk_mn DESC;

SELECT 
    loan_grade,
    ROUND(AVG(loan_status)*100, 2) as grade_default_rate,
    (SELECT ROUND(AVG(loan_status)*100, 2) FROM loans) as overall_default_rate
FROM loans 
GROUP BY loan_grade
HAVING AVG(loan_status)*100 > (SELECT AVG(loan_status)*100 FROM loans)
ORDER BY grade_default_rate DESC;
		