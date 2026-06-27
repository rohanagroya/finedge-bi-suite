# FinEdge Lending — Credit Risk BI Suite

**End-to-end Business Intelligence project for a fictional fintech lending company**  
**Tools:** SQL · Python · Excel · Power BI · GitHub  
**Dataset:** [Credit Risk Dataset](https://www.kaggle.com/datasets/laotse/credit-risk-dataset) — 32,581 rows, 12 columns

---

## Business Problem

FinEdge Lending is facing three critical issues:
- **NPA (Non-Performing Assets)** rate of 21.8% — over 4× the healthy industry benchmark of <5%
- **Revenue leakage** estimated at ~$107M due to defaulted loans
- **No data-driven underwriting policy** — lending decisions are grade-based but miss key risk signals

**This project delivers a full analytical solution: from raw data to executive dashboard.**

---

## Key Findings

| # | Finding | Impact |
|---|---------|--------|
| 1 | Portfolio default rate: **21.8%** | 4× above healthy benchmark |
| 2 | Grade D–G combined portfolio: **$39M+ at risk** | Restrict / reprice immediately |
| 3 | **30% DTI cliff effect** — default rate triples crossing 30% | Hard cap recommendation |
| 4 | RENT + DTI >30% → **100% default rate** (n=2,339) | Statistically confirmed risk zone |
| 5 | Total revenue leakage: **~$107M** worst-case | Quantified CFO-level business case |
| 6 | Credit tenure only 2.7% predictive vs Work-Life Ratio | Replace in scoring model |
| 7 | Debt Consolidation defaults at **2× the rate** of Venture | Intent-based rate floors needed |

---

## Project Structure

```
finedge-bi-suite/
├── 01_sql/
│   └── finedge_analysis.sql        # ~40 queries: cleaning → features → strategy
├── 02_python/
│   ├── finedge_analysis.ipynb      # Full notebook: cleaning, EDA, visualisations
│   └── visuals/                    # Saved PNG charts
├── 03_excel/
│   └── finedge_financial_model.xlsx # 3-tab financial model
├── 04_powerbi/
│   └── screenshots/                # Dashboard page screenshots
├── 05_report/
│   └── finedge_recommendations.pdf # 1-page executive summary
└── data/
    └── credit_risk_dataset.csv
```

---

## Tools & Techniques Used

**SQL (DB Browser for SQLite)**
- Pipeline architecture: raw → deduplicated → outlier-filtered → logically-validated → imputed
- Window functions: `RANK()`, `ROW_NUMBER()`, running totals with `SUM() OVER()`
- CTEs for multi-step business logic
- Dynamic subqueries (threshold auto-updates with data)
- Feature engineering: Work-Life Ratio, Interest Burden Ratio, Risk Segments

**Python (Jupyter Notebook)**
- Pandas for cleaning, groupby, pivot tables
- Matplotlib + Seaborn for 5 publication-quality charts
- Same cleaning sequence as SQL for cross-tool consistency
- Sample-size validation before drawing conclusions from 100% default-rate cells

**Excel**
- Tab 1: Unit Economics (CAC, LTV, LTV:CAC Ratio, Payback Period)
- Tab 2: 3-Year Revenue Projection (Best / Base / Bear scenarios)
- Tab 3: NPA Sensitivity Table (10%–35% default rate scenarios with dollar impact)
- All tabs linked via cross-sheet formulas — change one assumption, all tabs update

**Power BI**
- 3-page interactive dashboard (Overview / Risk Analysis / Customer Segmentation)
- DAX measures: `CALCULATE`, `SUMX`, `SWITCH(TRUE(), ...)` for calculated columns
- Cross-filtering across all visuals
- Conditional formatting heatmap (Grade × Home Ownership matrix)

---

## Data Cleaning Approach

The project follows a strict cleaning sequence (same in SQL, Python, and Power BI):

```
1. EXPLORE       → describe(), shape, null counts, categorical checks
2. DUPLICATES    → remove first (structural issue, independent of outliers)
3. OUTLIERS      → single-column impossibilities (age=144, emp=123, income=$6M)
4. CROSS-VALIDATE → multi-column logic (age vs employment length)
5. IMPUTE        → AFTER cleaning, so medians are not distorted by garbage values
6. SANITY CHECK  → verify final shape, confirm zero nulls, document % retained
```

**Data retention: 97.2%** (32,581 raw → 32,401 analysis-ready)

---

## Financial Model (Excel)

| Tab | What It Shows |
|-----|--------------|
| Unit Economics | CAC=$60, LTV=$226, LTV:CAC=3.8x, Payback=0.54 years |
| Revenue Projection | Best (15% NPA) vs Base (21.8%) vs Bear (30%) over 3 years |
| NPA Sensitivity | Every 1% rise in default rate = ~$X revenue loss (linked formula) |

---

## Power BI Dashboard

**Page 1 — Overview**
- 4 KPI cards: Total Loans, Defaults, Default Rate %, Portfolio Value
- Default Rate by Grade (bar chart, A–G sorted)
- Grade × Home Ownership risk heatmap (interactive matrix)

**Page 2 — Risk Analysis**
- DTI Cliff Effect chart (the 30% threshold visual)
- Revenue Leakage breakdown (3 measure cards)

**Page 3 — Customer Segmentation**
- Default Rate by Home Ownership
- Loan Purpose distribution (donut chart)

---

## How to Reproduce

1. Download `credit_risk_dataset.csv` from [Kaggle](https://www.kaggle.com/datasets/laotse/credit-risk-dataset)
2. Place it in `data/` folder
3. **SQL:** Open `01_sql/finedge_analysis.sql` in DB Browser for SQLite, import the CSV as table `loans`, run all queries in order
4. **Python:** Open Anaconda Prompt, `cd` to `02_python/`, run `jupyter notebook`, open `finedge_analysis.ipynb`, run all cells
5. **Excel:** Open `03_excel/finedge_financial_model.xlsx` — formulas auto-calculate
6. **Power BI:** Open Power BI Desktop, Get Data → CSV, follow Power Query cleaning steps

---

*Built as a portfolio project demonstrating end-to-end analytics capability across SQL, Python, Excel, and Power BI.*
