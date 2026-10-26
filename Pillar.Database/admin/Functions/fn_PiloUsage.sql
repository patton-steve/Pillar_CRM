-- A tenant's Pilo reports in the month starting @PeriodStart (UTC): Reports (ai.Generation rows that count toward the quota),
-- IncludedReports (the plan's IncludedAiReports, or Pilo.MonthlyReportsOverride), OverageReports, OveragePrice (the plan's
-- AiOveragePrice), OverageCap (the tenant's Pilo.OverageCapAmount; NULL = no cap), and OverageAmount (capped).
-- Uses the tenant's current plan.
CREATE FUNCTION admin.fn_PiloUsage (@TenantId INT, @PeriodStart DATE)
RETURNS TABLE
AS
RETURN
    SELECT u.Reports, u.IncludedReports,
           CASE WHEN u.Reports > u.IncludedReports THEN u.Reports - u.IncludedReports ELSE 0 END AS OverageReports,
           u.OveragePrice, u.OverageCap,
           CONVERT(DECIMAL(19,2),
               CASE WHEN u.Reports <= u.IncludedReports OR u.OveragePrice IS NULL THEN 0
                    WHEN u.OverageCap IS NOT NULL AND (u.Reports - u.IncludedReports) * u.OveragePrice > u.OverageCap THEN u.OverageCap
                    ELSE (u.Reports - u.IncludedReports) * u.OveragePrice END) AS OverageAmount
    FROM (
        SELECT (SELECT COUNT(*) FROM ai.Generation AS g
                WHERE g.TenantId = t.Id AND g.CountsTowardQuota = 1
                  AND g.CreatedAt >= CONVERT(DATETIME2(0), @PeriodStart)
                  AND g.CreatedAt < DATEADD(MONTH, 1, CONVERT(DATETIME2(0), @PeriodStart))) AS Reports,
               COALESCE(TRY_CONVERT(INT, ro.Value), p.IncludedAiReports) AS IncludedReports,
               p.AiOveragePrice AS OveragePrice,
               TRY_CONVERT(DECIMAL(19,2), cap.Value) AS OverageCap
        FROM admin.Tenant AS t
        JOIN admin.[Plan] AS p ON p.Id = t.PlanId
        OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Pilo.MonthlyReportsOverride') AS ro
        OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Pilo.OverageCapAmount') AS cap
        WHERE t.Id = @TenantId
    ) AS u;
