-- Shreepal

CREATE DATABASE IF NOT EXISTS inventory_db;
USE inventory_db;

CREATE TABLE forecast(
	date DATE,
    store_id VARCHAR(10),
    product_id VARCHAR(10),
    category VARCHAR(50),
    region VARCHAR(50),
	inventory_level INT,
    units_sold INT,
	units_ordered INT,
    demand_forecast DECIMAL(10,2) ,
    price DECIMAL(10,2) ,
    discount TINYINT,
	weather_condition VARCHAR(20),
	holiday_promotion BOOLEAN,
    competitor_pricing DECIMAL(10,2),
    seasonality VARCHAR(20),
	PRIMARY KEY (date, store_id, product_id)
);

SELECT*FROM forecast;
-- SELECT COUNT(*) FROM inventory_db.forecast;

-- -- SHOW VARIABLES LIKE 'secure_file_priv';
-- SHOW VARIABLES LIKE 'secure_file_priv'; -- which is C:\ProgramData\MySQL\MySQL Server 8.0\Uploads\
-- SHOW VARIABLES LIKE 'local_infile'; -- SET GLOBAL local_infile = 1;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/inventory_forecasting.csv'
 INTO TABLE forecast
 FIELDS TERMINATED BY ','
 IGNORE 1 LINES;

-- we will create different tables for better analysis

-- Table for Products
CREATE TABLE Products (
    ProductID VARCHAR(50) PRIMARY KEY,
    Category VARCHAR(50)
);

-- Table for Locations to uniquely identify each store location
CREATE TABLE Locations (
    LocationID INT AUTO_INCREMENT PRIMARY KEY,
    StoreID VARCHAR(50) NOT NULL,
    Region VARCHAR(50) NOT NULL,
    UNIQUE KEY uk_store_region (StoreID, Region)
);

-- Table for Date's dimensions
CREATE TABLE Dates (
    Date DATE PRIMARY KEY,
    DayOfWeek INT, -- 1- Sunday, 2 -Monday etc.
    Month INT,
    Quarter INT,
    Year INT
);

-- Central Fact Table for Inventory and Sales Metrics
CREATE TABLE InventoryFacts (
    Date DATE,
    LocationID INT,
    ProductID VARCHAR(50),
    InventoryLevel INT,
    UnitsSold INT,
    UnitsOrdered INT,
    DemandForecast DECIMAL(10, 2),
    Price DECIMAL(10, 2),
    Discount DECIMAL(5, 2),
    CompetitorPricing DECIMAL(10, 2),
    Weather_Condition VARCHAR(50),
    Holiday_Promotion BOOLEAN,
    Seasonality VARCHAR(50),

    PRIMARY KEY (Date, LocationID, ProductID),

    FOREIGN KEY (Date) REFERENCES Dates(Date),
    FOREIGN KEY (LocationID) REFERENCES Locations(LocationID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- load data from temp datatable forecast
INSERT INTO Products (ProductID, Category)
SELECT DISTINCT product_id, category
FROM forecast;

INSERT INTO Locations (StoreID, Region)
SELECT DISTINCT store_id, region
FROM forecast;

INSERT INTO Dates (Date, DayOfWeek, Month, Quarter, Year)
SELECT DISTINCT
    date,
    DAYOFWEEK(date),
    MONTH(date),
    QUARTER(date),
    YEAR(date)
FROM forecast;

INSERT INTO InventoryFacts (
    Date,
    LocationID,
    ProductID,
    InventoryLevel,
    UnitsSold,
    UnitsOrdered,
    DemandForecast,
    Price,
    Discount,
    CompetitorPricing,
    Weather_Condition,
    Holiday_Promotion,
    Seasonality
)
SELECT
    f.date,
    l.LocationID, -- We get the new LocationID from the Locations table
    f.product_id,
    f.inventory_level,
    f.units_sold,
    f.units_ordered,
    f.demand_forecast,
    f.price,
    f.discount,
    f.competitor_pricing,
    f.weather_condition, 
    f.holiday_promotion, 
    f.seasonality        
FROM
    forecast f
JOIN
    Locations l ON f.store_id = l.StoreID AND f.region = l.Region; -- to find the correct surrogate key (LocationID)


CREATE INDEX idx_fact_date ON InventoryFacts(Date);
CREATE INDEX idx_fact_location ON InventoryFacts(LocationID);
CREATE INDEX idx_fact_product ON InventoryFacts(ProductID);

-- Stock Level Calculations across stores
SELECT
    p.ProductID,
    p.Category,
    l.StoreID,
    l.Region,
    s.InventoryLevel,
    s.Date AS LastRecordedDate
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY ProductID, LocationID ORDER BY Date DESC) as rn
    FROM InventoryFacts
) s
JOIN Products as p ON s.ProductID = p.ProductID
JOIN Locations as l ON s.LocationID = l.LocationID
WHERE s.rn = 1  -- and oper. 
ORDER BY l.Region, l.StoreID, p.ProductID;

-- Reorder Point Estimation using historical trend
-- Note - I have created view to calculate the reorder point
    -- Reorder Point = (Average Sales * Lead Time Days) + Safety Stock, we will 7D lead + 7D safety

CREATE OR REPLACE VIEW DailySalesSummary AS
SELECT
    ProductID,
    LocationID,
    AVG(UnitsSold) as Avg_unitsold,
    STDDEV(UnitsSold) as SD_dailyunitsold -- SD is to measure volatility.
FROM InventoryFacts
WHERE UnitsSold > 0 -- for accurate avg
GROUP BY ProductID, LocationID;

SELECT
    p.ProductID,
    p.Category,
    l.StoreID,
    l.Region,
    CEILING(ds.Avg_unitsold) as AvgDaily_unitsold,
    CEILING(ds.SD_dailyunitsold) as Deviation_insales, -- extra alert from highly deviated product category 
    CEILING((ds.Avg_unitsold * 14)) AS Estimated_ReorderPoint    -- note I can add current inventory levels with Estimated_ReorderPoint but its asked in next sqlscrip
FROM DailySalesSummary as ds
JOIN Products p ON ds.ProductID = p.ProductID
JOIN Locations l ON ds.LocationID = l.LocationID
ORDER BY l.Region, ds.Avg_unitsold DESC;   -- to focus on region wise highest sold out products

-- Low Inventory Detection based on reorder point
WITH CurrentInventory AS (
    SELECT
        ProductID,
        LocationID,
        InventoryLevel
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER(PARTITION BY ProductID, LocationID ORDER BY Date DESC) as rn
        FROM InventoryFacts
    ) s
    WHERE s.rn = 1
),
ReorderPoints AS (
    SELECT
        ProductID,
        LocationID,
        CEILING((AVG(UnitsSold) *14)) AS EstimatedReorderPoint
    FROM InventoryFacts
    GROUP BY ProductID, LocationID
)
SELECT
    p.ProductID,
    p.Category,
    l.StoreID,
    l.Region,
    ci.InventoryLevel,
    rp.EstimatedReorderPoint,
    (rp.EstimatedReorderPoint - ci.InventoryLevel) AS Shortfall 
FROM CurrentInventory as ci
JOIN ReorderPoints as rp  ON ci.ProductID = rp.ProductID AND ci.LocationID = rp.LocationID
JOIN Products p ON ci.ProductID = p.ProductID
JOIN Locations l ON ci.LocationID = l.LocationID
WHERE ci.InventoryLevel < rp.EstimatedReorderPoint
ORDER BY Shortfall DESC;   -- most shortfall product at top

-- Inventory Turnover Analysis
--     Turnover Ratio = COGS / Avg Inventory
WITH MonthlyMetrics AS (
    SELECT
        p.Category,
        DATE_FORMAT(f.Date, '%Y-%m-01') AS SalesMonth,
        SUM(f.UnitsSold * f.Price) AS MonthlyCOGS,
        SUM(f.InventoryLevel * f.Price) / COUNT(DISTINCT f.Date) AS AvgMonthlyInventoryValue
    FROM InventoryFacts f
    JOIN Products p ON f.ProductID = p.ProductID
    GROUP BY p.Category, SalesMonth
)
SELECT
    Category,
    SalesMonth,
    MonthlyCOGS,
    AvgMonthlyInventoryValue,
    CASE
        WHEN AvgMonthlyInventoryValue > 0 THEN MonthlyCOGS / AvgMonthlyInventoryValue
        ELSE 0
    END AS InventoryTurnoverRatio
FROM MonthlyMetrics
ORDER BY Category, SalesMonth;

-- Fast-Selling v/s Slow-Moving Products
--     I have catagories in ABC- A-top70% B-nxt20% C-rest10%
WITH ProductRevenue AS (
    SELECT
        ProductID,
        SUM(UnitsSold * Price) AS TotalRevenue
    FROM InventoryFacts
    GROUP BY ProductID
),
CumulativeRevenue AS (
    SELECT
        ProductID,
        TotalRevenue,
        SUM(TotalRevenue) OVER (ORDER BY TotalRevenue DESC) as CumulativeSum,
        SUM(TotalRevenue) OVER () as GrandTotal
    FROM ProductRevenue
)
SELECT
    p.ProductID,
    p.Category,
    cr.TotalRevenue,
    (cr.CumulativeSum / cr.GrandTotal) * 100 AS CumulativePercentage,
    CASE
        WHEN (cr.CumulativeSum / cr.GrandTotal) * 100 <= 70 THEN 'A'
        WHEN (cr.CumulativeSum / cr.GrandTotal) * 100 <= 90 THEN 'B'
        ELSE 'C'
    END AS ABC_Category
FROM CumulativeRevenue as cr
JOIN Products as p ON cr.ProductID = p.ProductID
ORDER BY TotalRevenue DESC;

-- Summary Reports with KPIs
-- 1st stockout rate
SELECT
    p.ProductID,
    p.Category,
    l.StoreID,
    l.Region,
    COUNT(*) AS TotalDaysTracked,
    SUM(CASE WHEN f.InventoryLevel = 0 THEN f.DemandForecast ELSE 0 END) AS EstimatedLostSales,
    SUM(CASE WHEN f.InventoryLevel = 0 THEN 1 ELSE 0 END) AS DaysAtZeroInventory,
    (SUM(CASE WHEN f.InventoryLevel = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS StockoutRatePercentage
FROM InventoryFacts f
JOIN Products p ON f.ProductID = p.ProductID
JOIN Locations l ON f.LocationID = l.LocationID
GROUP BY p.ProductID, p.Category, l.StoreID, l.Region
HAVING SUM(CASE WHEN f.InventoryLevel = 0 THEN 1 ELSE 0 END) > 0
ORDER BY StockoutRatePercentage DESC;

-- 2nd Demand Forecast Accuracy
SELECT
    p.Category,
    f.Date,
    SUM(f.DemandForecast) as TotalForecastedDemand,
    SUM(f.UnitsSold) as TotalActualSales,
    (SUM(f.UnitsSold) - SUM(f.DemandForecast)) AS ForecastError,
    -- Mean Absolute Percentage Error (MAPE)
    AVG(ABS((f.UnitsSold - f.DemandForecast) / NULLIF(f.UnitsSold, 0))) * 100 AS MAPE_Percentage
FROM InventoryFacts f
JOIN Products p ON f.ProductID = p.ProductID
GROUP BY p.Category, f.Date
ORDER BY p.Category, f.Date;

-- overall KPI dashboard summery
-- Query 3.3: Overall Inventory KPI Dashboard Summary (Corrected)
WITH Last30Days AS (
    SELECT *
    FROM InventoryFacts
    WHERE Date >= (SELECT MAX(Date) FROM InventoryFacts) - INTERVAL '30' DAY
),
CurrentInventory AS (
    SELECT
        ProductID,
        LocationID,
        InventoryLevel,
        Price
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER(PARTITION BY ProductID, LocationID ORDER BY Date DESC) as rn
        FROM InventoryFacts
    ) s
    WHERE s.rn = 1
)
SELECT
    p.Category,
    SUM(ci.InventoryLevel * ci.Price) AS TotalInventoryValue,
    30 / (SUM(l30.UnitsSold * l30.Price) / NULLIF(SUM(l30.InventoryLevel * l30.Price) / COUNT(DISTINCT l30.Date), 0)) AS AvgInventoryDays_Last30,
    (SUM(CASE WHEN l30.InventoryLevel = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS CategoryStockoutRate_Last30
FROM
    Last30Days l30
JOIN
    Products as p ON l30.ProductID = p.ProductID
JOIN
    CurrentInventory as ci ON l30.ProductID = ci.ProductID
GROUP BY
    p.Category
ORDER BY
    TotalInventoryValue DESC;
    
    

