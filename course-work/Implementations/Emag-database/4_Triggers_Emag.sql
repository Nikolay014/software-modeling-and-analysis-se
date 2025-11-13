-- Тригер: преизчислява TOTAL_AMOUNT на поръчка при промени по ORDER_PRODUCT.
-- Работи при INSERT, UPDATE и DELETE. Поправя и NULL UNIT_PRICE с PRODUCT.PRICE.

CREATE OR ALTER TRIGGER trg_OrderProduct_RecalcOrderTotal
ON ORDER_PRODUCT
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- 1) Поправи UNIT_PRICE, ако е NULL (за ново/обновено)
    IF EXISTS (SELECT 1 FROM inserted WHERE UNIT_PRICE IS NULL)
    BEGIN
        UPDATE op
        SET UNIT_PRICE = p.PRICE
        FROM ORDER_PRODUCT op
        JOIN inserted i  ON i.ORDER_ID = op.ORDER_ID AND i.PRODUCT_ID = op.PRODUCT_ID
        JOIN PRODUCT  p  ON p.PRODUCT_ID = op.PRODUCT_ID
        WHERE op.UNIT_PRICE IS NULL;
    END

    -- 2) Намери засегнатите поръчки
    ;WITH affected AS (
        SELECT ORDER_ID FROM inserted
        UNION
        SELECT ORDER_ID FROM deleted
    )
    -- 3) Пресметни новия тотал от редовете (Quantity * Unit_Price)
    UPDATE o
    SET TOTAL_AMOUNT = ISNULL((
            SELECT CAST(SUM(op.QUANTITY * op.UNIT_PRICE) AS DECIMAL(10,2))
            FROM ORDER_PRODUCT op
            WHERE op.ORDER_ID = o.ORDER_ID
        ), 0.00)
    FROM [ORDER] o
    JOIN affected a ON a.ORDER_ID = o.ORDER_ID;
END
GO

CREATE OR ALTER TRIGGER trg_UpdateSellerAverageRating
ON dbo.REVIEW
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SellerId INT;

    -- Определи кой търговец е засегнат (взимаме го от продукта)
    SELECT TOP 1 @SellerId = p.SELLER_ID
    FROM dbo.PRODUCT p
    JOIN (
        SELECT PRODUCT_ID FROM inserted
        UNION
        SELECT PRODUCT_ID FROM deleted
    ) x ON x.PRODUCT_ID = p.PRODUCT_ID;

    -- Ако няма засегнат търговец, излизаме
    IF @SellerId IS NULL
        RETURN;

    -- Пресмятаме новия среден рейтинг за този търговец
    DECLARE @NewAvg DECIMAL(4,2);

    SELECT @NewAvg = AVG(CAST(r.RATING AS DECIMAL(4,2)))
    FROM dbo.REVIEW r
    JOIN dbo.PRODUCT pr ON pr.PRODUCT_ID = r.PRODUCT_ID
    WHERE pr.SELLER_ID = @SellerId;

    -- Обновяваме средната оценка (ако няма ревюта, става 0)
    UPDATE dbo.SELLER
    SET AVERAGE_RATING = ISNULL(@NewAvg, 0.00)
    WHERE SELLER_ID = @SellerId;
END;
GO

-- Пример: добавяме ред към поръчка без UNIT_PRICE (ще вземе PRODUCT.PRICE)
INSERT INTO ORDER_PRODUCT (ORDER_ID, PRODUCT_ID, QUANTITY, UNIT_PRICE)
VALUES (1, 1, 2, NULL);

-- Проверка: тоталът се е актуализирал
SELECT ORDER_ID, TOTAL_AMOUNT FROM [ORDER] WHERE ORDER_ID = 1;

-- Обновяване на количество -> тоталът пак се актуализира
UPDATE ORDER_PRODUCT
SET QUANTITY = QUANTITY + 1
WHERE ORDER_ID = 1 AND PRODUCT_ID = 1;

SELECT ORDER_ID, TOTAL_AMOUNT FROM [ORDER] WHERE ORDER_ID = 1;

-- Изтриване на ред -> тоталът се преизчислява
DELETE FROM ORDER_PRODUCT
WHERE ORDER_ID = 1 AND PRODUCT_ID = 1;

SELECT ORDER_ID, TOTAL_AMOUNT FROM [ORDER] WHERE ORDER_ID = 1;