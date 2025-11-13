-- Функция, която извежда среден рейтинг за даден продукт.

CREATE OR ALTER FUNCTION PRODUCT_AVERAGE_RATING(@PRODUCT_ID INT) 
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @PROD_NAME VARCHAR(100), @AVG_RATING NUMERIC(4,2);

    
    SELECT @PROD_NAME = NAME
    FROM PRODUCT
    WHERE PRODUCT_ID = @PRODUCT_ID;

    
    SELECT @AVG_RATING = ISNULL(AVG(CAST(RATING AS DECIMAL(4,2))), 0.00)
    FROM REVIEW
    WHERE PRODUCT_ID = @PRODUCT_ID;

    RETURN ISNULL(@PROD_NAME, 'Непознат продукт') 
        + ' (ID = ' + CAST(@PRODUCT_ID AS VARCHAR) + '), среден рейтинг: ' 
        + CAST(@AVG_RATING AS VARCHAR) + '.';
END
GO

SELECT dbo.PRODUCT_AVERAGE_RATING(PRODUCT_ID) AS PRODUCT_AVERAGE_RATING_RESULT
FROM PRODUCT;

-- Функция, която извежда среден рейтинг за даден продавач (SELLER).

CREATE OR ALTER FUNCTION SELLER_AVERAGE_RATING(@SELLER_ID INT)
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @SELLER_NAME VARCHAR(100), @AVG_RATING NUMERIC(4,2);

    -- Взимаме името на фирмата
    SELECT @SELLER_NAME = COMPANY_NAME
    FROM SELLER
    WHERE SELLER_ID = @SELLER_ID;

    -- Изчисляваме средния рейтинг по всички продукти на този продавач
    SELECT @AVG_RATING = ISNULL(AVG(CAST(R.RATING AS DECIMAL(4,2))), 0.00)
    FROM PRODUCT P
    JOIN REVIEW R ON R.PRODUCT_ID = P.PRODUCT_ID
    WHERE P.SELLER_ID = @SELLER_ID;

    RETURN ISNULL(@SELLER_NAME, 'Непознат продавач')
        + ' (ID = ' + CAST(@SELLER_ID AS VARCHAR) + '), среден рейтинг: '
        + CAST(@AVG_RATING AS VARCHAR) + '.';
END
GO

SELECT dbo.SELLER_AVERAGE_RATING(SELLER_ID) AS SELLER_AVERAGE_RATING_RESULT
FROM SELLER;


-- Отчет: Производителност на продавачите за период (включително @DateTo)
CREATE OR ALTER FUNCTION dbo.SELLER_PERFORMANCE_PERIOD
(
    @DateFrom DATE,
    @DateTo   DATE
)
RETURNS TABLE
AS
RETURN
WITH PeriodOrders AS (
    SELECT o.ORDER_ID, o.ORDER_DATE, o.USER_ID
    FROM [ORDER] o
    WHERE o.ORDER_DATE >= @DateFrom
      AND o.ORDER_DATE < DATEADD(DAY, 1, @DateTo)  -- правим @DateTo включително
),
Lines AS (
    SELECT 
        po.ORDER_ID,
        po.ORDER_DATE,
        po.USER_ID,
        s.SELLER_ID,
        s.COMPANY_NAME,
        s.COUNTRY,
        p.PRODUCT_ID,
        p.NAME AS PRODUCT_NAME,
        op.QUANTITY,
        op.UNIT_PRICE,
        CAST(op.QUANTITY * op.UNIT_PRICE AS DECIMAL(18,2)) AS LineTotal
    FROM PeriodOrders po
    JOIN ORDER_PRODUCT op ON op.ORDER_ID = po.ORDER_ID
    JOIN PRODUCT p        ON p.PRODUCT_ID = op.PRODUCT_ID
    JOIN SELLER s         ON s.SELLER_ID = p.SELLER_ID
),
AggSeller AS (
    SELECT
        l.SELLER_ID,
        l.COMPANY_NAME,
        l.COUNTRY,
        COUNT(DISTINCT l.ORDER_ID)                       AS OrdersCount,
        COUNT(DISTINCT l.USER_ID)                        AS DistinctCustomers,
        SUM(l.QUANTITY)                                  AS ItemsSold,
        CAST(SUM(l.LineTotal) AS DECIMAL(18,2))          AS Revenue
    FROM Lines l
    GROUP BY l.SELLER_ID, l.COMPANY_NAME, l.COUNTRY
),
RatingsPeriod AS (
    -- Среден рейтинг по ревютата за продуктите на продавача в периода (по CREATED_AT)
    SELECT 
        p.SELLER_ID,
        CAST(AVG(CAST(r.RATING AS DECIMAL(4,2))) AS DECIMAL(4,2)) AS AvgRatingPeriod
    FROM REVIEW r
    JOIN PRODUCT p ON p.PRODUCT_ID = r.PRODUCT_ID
    WHERE r.CREATED_AT >= @DateFrom
      AND r.CREATED_AT <  DATEADD(DAY, 1, @DateTo)
    GROUP BY p.SELLER_ID
),
TopProduct AS (
    -- Топ продукт на продавача по оборот за периода
    SELECT
        l.SELLER_ID,
        tp.PRODUCT_ID,
        tp.PRODUCT_NAME,
        CAST(tp.Rev AS DECIMAL(18,2)) AS TopProductRevenue
    FROM Lines l
    CROSS APPLY (
        SELECT TOP 1 l2.PRODUCT_ID, l2.PRODUCT_NAME, SUM(l2.LineTotal) AS Rev
        FROM Lines l2
        WHERE l2.SELLER_ID = l.SELLER_ID
        GROUP BY l2.PRODUCT_ID, l2.PRODUCT_NAME
        ORDER BY SUM(l2.LineTotal) DESC, l2.PRODUCT_ID
    ) tp
    GROUP BY l.SELLER_ID, tp.PRODUCT_ID, tp.PRODUCT_NAME, tp.Rev
)
SELECT
    a.SELLER_ID,
    a.COMPANY_NAME,
    a.COUNTRY,
    a.OrdersCount,
    a.DistinctCustomers,
    a.ItemsSold,
    a.Revenue,
    -- средна стойност на поръчка за този продавач (оборот / брой поръчки)
    CAST(CASE WHEN a.OrdersCount = 0 THEN 0 ELSE a.Revenue * 1.0 / a.OrdersCount END AS DECIMAL(18,2)) AS AvgOrderValue,
    -- средна цена на артикул (оборот / бройки)
    CAST(CASE WHEN a.ItemsSold   = 0 THEN 0 ELSE a.Revenue * 1.0 / a.ItemsSold   END AS DECIMAL(18,2)) AS AvgItemPrice,
    ISNULL(rp.AvgRatingPeriod, 0.00) AS AvgRatingPeriod,
    tp.PRODUCT_ID    AS TopProductId,
    tp.PRODUCT_NAME  AS TopProductName,
    tp.TopProductRevenue
FROM AggSeller a
LEFT JOIN RatingsPeriod rp ON rp.SELLER_ID = a.SELLER_ID
LEFT JOIN TopProduct   tp ON tp.SELLER_ID = a.SELLER_ID;
GO

-- 1) Всички продавачи за Q3 2025
SELECT *
FROM dbo.SELLER_PERFORMANCE_PERIOD('2025-07-01','2025-09-30')
ORDER BY Revenue DESC;

-- 2) Топ 5 по оборот за октомври 2025
SELECT TOP 5 *
FROM dbo.SELLER_PERFORMANCE_PERIOD('2025-10-01','2025-10-31')
ORDER BY Revenue DESC;

-- 3) Продавачи с AvgRatingPeriod < 3 за 2025
SELECT *
FROM dbo.SELLER_PERFORMANCE_PERIOD('2025-01-01','2025-12-31')
WHERE AvgRatingPeriod < 3
ORDER BY AvgRatingPeriod ASC;

-- 4) Продавачи с поне 50 бройки продадени и > 10 000 лв. оборот
SELECT *
FROM dbo.SELLER_PERFORMANCE_PERIOD('2025-01-01','2025-12-31')
WHERE ItemsSold >= 50 AND Revenue > 10000
ORDER BY Revenue DESC;
