-- Процедура, която извежда броя поръчки и общо похарчена сума по потребители.

CREATE PROCEDURE USER_ORDERS
AS
SELECT 
    U.USERNAME,
    U.CITY,
    COUNT(O.ORDER_ID)                 AS ORDER_COUNT,
    CAST(ISNULL(SUM(O.TOTAL_AMOUNT), 0.00) AS DECIMAL(12,2)) AS TOTAL_SPENT
FROM [USER] U
LEFT JOIN [ORDER] O
    ON O.USER_ID = U.USER_ID
GROUP BY U.USERNAME, U.CITY
ORDER BY TOTAL_SPENT DESC, ORDER_COUNT DESC;


EXEC USER_ORDERS;

-- Процедура, която връща като параметри обща продадена бройка и оборот за продукт.

CREATE PROCEDURE GET_PRODUCT_TOTALS 
    @PRODUCT_ID     INT,
    @TOTAL_QTY      INT OUTPUT,
    @TOTAL_REVENUE  DECIMAL(12,2) OUTPUT
AS
BEGIN
    SELECT 
        @TOTAL_QTY = ISNULL(SUM(OP.QUANTITY), 0)
    FROM ORDER_PRODUCT OP
    WHERE OP.PRODUCT_ID = @PRODUCT_ID;

    SELECT
        @TOTAL_REVENUE = CAST(ISNULL(SUM(OP.QUANTITY * OP.UNIT_PRICE), 0.00) AS DECIMAL(12,2))
    FROM ORDER_PRODUCT OP
    WHERE OP.PRODUCT_ID = @PRODUCT_ID;
END
GO

-- Пример за извикване:
DECLARE @QTY INT, @REV DECIMAL(12,2);
EXEC GET_PRODUCT_TOTALS 1, @QTY OUTPUT, @REV OUTPUT;
PRINT 'Общо бройки: ' + CAST(@QTY AS VARCHAR(20));
PRINT 'Оборот: ' + CAST(@REV AS VARCHAR(50));
3) Топ продукти на продавач по оборот
sql
Копиране на код
-- Процедура, която извежда продуктите на продавач с бройки и оборот, подредени по оборот.

CREATE PROCEDURE SELLER_TOP_PRODUCTS
    @SELLER_ID INT
AS
SELECT 
    P.PRODUCT_ID,
    P.NAME                  AS PRODUCT_NAME,
    SUM(OP.QUANTITY)        AS TOTAL_QTY,
    CAST(SUM(OP.QUANTITY * OP.UNIT_PRICE) AS DECIMAL(18,2)) AS REVENUE
FROM PRODUCT P
JOIN ORDER_PRODUCT OP
    ON OP.PRODUCT_ID = P.PRODUCT_ID
WHERE P.SELLER_ID = @SELLER_ID
GROUP BY P.PRODUCT_ID, P.NAME
ORDER BY REVENUE DESC, TOTAL_QTY DESC;


EXEC SELLER_TOP_PRODUCTS 1;

-- Процедура, която извежда поръчките в период (@DateFrom..@DateTo включително)
-- с тотал по редове, реално платено и баланс.

CREATE PROCEDURE ORDERS_IN_PERIOD
    @DateFrom DATE,
    @DateTo   DATE
AS
SELECT
    o.ORDER_ID,
    o.ORDER_NUMBER,
    o.ORDER_DATE,
    u.USERNAME,
    o.STATUS,
    -- тотал от детайлите (по-надежден от записания)
    CAST(SUM(op.QUANTITY * op.UNIT_PRICE) AS DECIMAL(18,2)) AS CalculatedTotal,
    -- платено по поръчка
    CAST(ISNULL( (SELECT SUM(p.AMOUNT) FROM PAYMENT p WHERE p.ORDER_ID = o.ORDER_ID), 0.00) AS DECIMAL(18,2)) AS PaidAmount,
    -- баланс
    CAST(
        SUM(op.QUANTITY * op.UNIT_PRICE)
        - ISNULL( (SELECT SUM(p.AMOUNT) FROM PAYMENT p WHERE p.ORDER_ID = o.ORDER_ID), 0.00)
        AS DECIMAL(18,2)
    ) AS Balance
FROM [ORDER] o
JOIN [USER] u       ON u.USER_ID = o.USER_ID
JOIN ORDER_PRODUCT op ON op.ORDER_ID = o.ORDER_ID
WHERE o.ORDER_DATE >= @DateFrom
  AND o.ORDER_DATE <  DATEADD(DAY, 1, @DateTo)  -- правим @DateTo включително
GROUP BY o.ORDER_ID, o.ORDER_NUMBER, o.ORDER_DATE, u.USERNAME, o.STATUS
ORDER BY o.ORDER_DATE DESC, o.ORDER_ID DESC;
GO

-- Пример за извикване:
EXEC ORDERS_IN_PERIOD '2025-10-01','2025-10-31';