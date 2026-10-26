-- Back-office home (Steve 2026-10-22). First result set, one row for @Month (default this month, UTC):
--   Mrr                 plan prices plus extra seats of ACTIVE tenants, as of now
--   FeeRevenue          platform fees accrued in the month, net of reversals
--   ActiveTenants, PendingApplications, SuspendedTenants
--   FailedCharges, FailedChargeBalance   PAST_DUE statements and what they still owe
--   PiloReports, AiCostUsd              Pilo reports and model cost in the month (ai.Generation)
--   AiRevenue           AI plan prices of ACTIVE tenants plus Pilo overage so far (uncapped estimate before the statement)
--   SignUps, Approvals, Churned         tenants created, approved and cancelled in the month
--   UnreadInbox         unread back-office inbox items
-- Second result set (@IncludeTrend = 1): the same month-level counts for the 12 months up to @Month, for the trend chart.
CREATE PROCEDURE admin.usp_PlatformDashboard
    @Month          DATE = NULL,
    @IncludeTrend   BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET @Month = DATEFROMPARTS(YEAR(COALESCE(@Month, @Today)), MONTH(COALESCE(@Month, @Today)), 1);
    DECLARE @From DATETIME2(0) = CAST(@Month AS DATETIME2(0)), @To DATETIME2(0) = DATEADD(MONTH, 1, CAST(@Month AS DATETIME2(0)));

    SELECT @Month AS Month,
           (SELECT ISNULL(SUM(p.MonthlyPrice + s.ExtraSeatsMonthly), 0)
            FROM admin.Tenant AS t JOIN admin.[Plan] AS p ON p.Id = t.PlanId
            CROSS APPLY admin.fn_TenantSeats(t.Id) AS s
            WHERE t.Status = 'ACTIVE') AS Mrr,
           (SELECT ISNULL(SUM(f.FeeAmount), 0) FROM admin.PlatformFee AS f WHERE f.AccruedAt >= @From AND f.AccruedAt < @To) AS FeeRevenue,
           (SELECT COUNT(*) FROM admin.Tenant WHERE Status = 'ACTIVE') AS ActiveTenants,
           (SELECT COUNT(*) FROM admin.Tenant WHERE Status = 'PENDING_REVIEW') AS PendingApplications,
           (SELECT COUNT(*) FROM admin.Tenant WHERE Status = 'SUSPENDED') AS SuspendedTenants,
           (SELECT COUNT(*) FROM admin.PlatformStatement WHERE Status = 'PAST_DUE') AS FailedCharges,
           (SELECT ISNULL(SUM(BalanceDue), 0) FROM admin.PlatformStatement WHERE Status = 'PAST_DUE') AS FailedChargeBalance,
           (SELECT COUNT(*) FROM ai.Generation WHERE CountsTowardQuota = 1 AND CreatedAt >= @From AND CreatedAt < @To) AS PiloReports,
           (SELECT ISNULL(SUM(CostUsd), 0) FROM ai.Generation WHERE CreatedAt >= @From AND CreatedAt < @To) AS AiCostUsd,
           (SELECT ISNULL(SUM(p.MonthlyPrice), 0) FROM admin.Tenant AS t JOIN admin.[Plan] AS p ON p.Id = t.PlanId
            WHERE t.Status = 'ACTIVE' AND p.IncludedAiReports > 0)
           + (SELECT ISNULL(SUM(u.OverageAmount), 0) FROM admin.Tenant AS t CROSS APPLY admin.fn_PiloUsage(t.Id, @Month) AS u
              WHERE t.Status = 'ACTIVE') AS AiRevenue,
           (SELECT COUNT(*) FROM admin.Tenant WHERE CreatedAt >= @From AND CreatedAt < @To) AS SignUps,
           (SELECT COUNT(*) FROM admin.Tenant WHERE ApprovedAt >= @From AND ApprovedAt < @To) AS Approvals,
           (SELECT COUNT(*) FROM admin.Tenant WHERE CancelledAt >= @From AND CancelledAt < @To) AS Churned,
           (SELECT COUNT(*) FROM admin.PlatformNotification WHERE ReadAt IS NULL) AS UnreadInbox;

    IF @IncludeTrend = 1
    BEGIN
        WITH m AS (
            SELECT DATEADD(MONTH, -v.MonthsBack, @Month) AS Month
            FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11)) AS v (MonthsBack)
        )
        SELECT m.Month,
               (SELECT COUNT(*) FROM admin.Tenant AS t WHERE t.CreatedAt >= m.Month AND t.CreatedAt < DATEADD(MONTH, 1, m.Month)) AS SignUps,
               (SELECT COUNT(*) FROM admin.Tenant AS t WHERE t.ApprovedAt >= m.Month AND t.ApprovedAt < DATEADD(MONTH, 1, m.Month)) AS Approvals,
               (SELECT COUNT(*) FROM admin.Tenant AS t WHERE t.CancelledAt >= m.Month AND t.CancelledAt < DATEADD(MONTH, 1, m.Month)) AS Churned,
               (SELECT ISNULL(SUM(f.FeeAmount), 0) FROM admin.PlatformFee AS f
                WHERE f.AccruedAt >= m.Month AND f.AccruedAt < DATEADD(MONTH, 1, m.Month)) AS FeeRevenue,
               (SELECT ISNULL(SUM(s.AmountDue), 0) FROM admin.PlatformStatement AS s
                WHERE s.PeriodStart = m.Month AND s.Status <> 'VOID') AS Billed,
               (SELECT ISNULL(SUM(g.CostUsd), 0) FROM ai.Generation AS g
                WHERE g.CreatedAt >= m.Month AND g.CreatedAt < DATEADD(MONTH, 1, m.Month)) AS AiCostUsd
        FROM m
        ORDER BY m.Month;
    END;
END;
