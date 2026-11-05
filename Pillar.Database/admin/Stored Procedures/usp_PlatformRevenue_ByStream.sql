-- Platform revenue by stream for the back office home (Pillar staff, handoff 26), one row per month for the @Months months up to
-- @Month (default this month), from live statements for each month: Fees (FEE and REVERSAL lines, then CAP and MINIMUM), Plans,
-- Seats, Pilo, Services, Credits and Billed (AmountDue). FeesAccrued is the fees accrued in the month before the cap, so the
-- current month shows something before its statement exists.
CREATE PROCEDURE admin.usp_PlatformRevenue_ByStream
    @Month  DATE = NULL,
    @Months INT = 12
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET @Month = DATEFROMPARTS(YEAR(COALESCE(@Month, @Today)), MONTH(COALESCE(@Month, @Today)), 1);
    SET @Months = CASE WHEN @Months BETWEEN 1 AND 36 THEN @Months ELSE 12 END;

    WITH n AS (
        SELECT v.Back FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),
                                   (18),(19),(20),(21),(22),(23),(24),(25),(26),(27),(28),(29),(30),(31),(32),(33),(34),(35)) AS v (Back)
        WHERE v.Back < @Months
    ), m AS (
        SELECT DATEADD(MONTH, -n.Back, @Month) AS Month FROM n
    )
    SELECT m.Month,
           ISNULL(SUM(CASE WHEN l.LineType IN ('FEE', 'REVERSAL', 'CAP', 'MINIMUM') THEN l.Amount END), 0) AS Fees,
           ISNULL(SUM(CASE WHEN l.LineType = 'PLAN' THEN l.Amount END), 0) AS Plans,
           ISNULL(SUM(CASE WHEN l.LineType = 'SEATS' THEN l.Amount END), 0) AS Seats,
           ISNULL(SUM(CASE WHEN l.LineType = 'PILO' THEN l.Amount END), 0) AS Pilo,
           ISNULL(SUM(CASE WHEN l.LineType = 'SERVICE' THEN l.Amount END), 0) AS Services,
           ISNULL(SUM(CASE WHEN l.LineType = 'CREDIT' THEN l.Amount END), 0) AS Credits,
           (SELECT ISNULL(SUM(s2.AmountDue), 0) FROM admin.PlatformStatement AS s2 WHERE s2.PeriodStart = m.Month AND s2.Status <> 'VOID') AS Billed,
           (SELECT ISNULL(SUM(f.FeeAmount), 0) FROM admin.PlatformFee AS f
            WHERE f.AccruedAt >= CAST(m.Month AS DATETIME2(0)) AND f.AccruedAt < DATEADD(MONTH, 1, CAST(m.Month AS DATETIME2(0)))) AS FeesAccrued
    FROM m
    LEFT JOIN admin.PlatformStatement AS s ON s.PeriodStart = m.Month AND s.Status <> 'VOID'
    LEFT JOIN admin.PlatformStatementLine AS l ON l.TenantId = s.TenantId AND l.StatementId = s.Id
    GROUP BY m.Month
    ORDER BY m.Month;
END;
