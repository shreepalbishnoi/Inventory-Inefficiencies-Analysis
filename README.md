# Inventory Inefficiencies Analysis using Advanced SQL

The system is built using a **data warehouse approach (star schema)** and derives actionable insights through **analytical SQL queries and KPI dashboards**.

---

## Objectives

* Analyze inventory performance across stores and regions
* Detect stockouts and quantify lost sales
* Optimize reorder points using historical demand
* Classify products using ABC analysis
* Evaluate demand forecast accuracy (MAPE)
* Build KPI-driven insights for decision-making

---

## Data Model (Star Schema)

The project follows a structured warehouse design:

* **Fact Table:** `InventoryFacts`
* **Dimension Tables:**

  * `Products`
  * `Locations`
  * `Dates`

Refer to ER Diagram: 

---

## Tech Stack

* SQL (MySQL 8.0)
* Advanced SQL Features:

  * Window Functions (`ROW_NUMBER`, `SUM OVER`)
  * CTEs (`WITH`)
  * Views
  * Aggregations & KPI calculations
* Data Modeling (Star Schema)

---

## Dataset & Setup

### 1. Create Database

```sql
CREATE DATABASE inventory_db;
USE inventory_db;
```

### 2. Load Data

```sql
LOAD DATA INFILE 'inventory_forecasting.csv'
INTO TABLE forecast
FIELDS TERMINATED BY ','
IGNORE 1 LINES;
```

refer SQL Script: 

---

## Key Analytical Modules

### 1. Inventory Tracking

* Latest stock levels per product-store
* Region-wise inventory distribution

### 2. Reorder Point Estimation

* Formula:

  ```
  Reorder Point = Avg Daily Sales × (Lead Time + Safety Stock)
  ```
* Uses rolling averages + standard deviation

### 3. Low Inventory Detection

* Identifies products below reorder threshold
* Calculates **shortfall quantity**

### 4. Inventory Turnover Analysis

* Measures efficiency of stock movement:

  ```
  Turnover = COGS / Avg Inventory
  ```

### 5. ABC Analysis (Revenue-Based Segmentation)

* A: Top 70% revenue
* B: Next 20%
* C: Bottom 10%

### 6. Stockout Analysis

* Stockout rate per product/store
* Estimated lost sales

### 7. Demand Forecast Accuracy

* Metric: **MAPE (Mean Absolute Percentage Error)**

---

## KPI Dashboard Insights

 Dashboard Reference: 

From the **Inventory KPI Dashboard (Page 1)**:

* 💰 Total Inventory Value: **$1.25M (+5%)**
* ⏳ Avg Inventory Days: **42 days**
* ⚠️ Stockout Rate: **8.5%**
* 📉 Forecast Accuracy (MAPE): **22%**

### Key Observations

* Groceries have highest turnover (~7.8), Home Goods lowest (~3.1)
* 15% of products generate 70% revenue (A-class)
* North region shows highest stockout rate (~12.5%)
* Multiple products below reorder point (critical shortages)

---
## Recommendations

* Implement **dynamic reorder points**
* Optimize or remove **C-class products**
* Improve **regional supply chain (especially North)**
* Upgrade to **ML-based demand forecasting models**

---

## How to Run
1. Import dataset
2. Execute SQL script sequentially
3. Run analytical queries
4. Visualize outputs (Power BI / Excel / Tableau optional)

---

## Repository Structure

```
├── data/
│   └── inventory_forecasting.csv
├── sql/
│   └── SQL script.sql
├── docs/
│   ├── ER-diagram.pdf
│   ├── Inventory KPI Dashboard.pdf
│   └── KPI_Dashboard.png
└── README.md
```

