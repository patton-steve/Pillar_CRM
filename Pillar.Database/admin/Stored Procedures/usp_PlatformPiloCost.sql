-- Back office > Pilo cost: per tenant for @Month (default this month), Pilo reports and other calls, model cost (ai.Generation),
-- and revenue (the AI plan price plus overage, capped) with the margin. Tenants with no Pilo plan and no calls are left out.
-- Uses each tenant's current plan.
CREATE PROCEDURE admin.usp_PlatformPiloCost
    @Month DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET @Month = DATEFROMPARTS(YEAR(COALESCE(@Month, @Today)), MONTH(COALESCE(@Month, @Today)), 1);
    DECLARE @From DATETIME2(0) = CAST(@Month AS DATETIME2(0)), @To DATETIME2(0) = DATEADD(MONTH, 1, CAST(@Month AS DATETIME2(0)));

    SELECT x.TenantId, x.TenantName, x.PlanCode, x.Reports, x.IncludedReports, x.OverageReports, x.Calls,
           x.InputTokens, x.OutputTokens, x.AiCostUsd, x.PlanRevenue, x.OverageRevenue,
           x.PlanRevenue + x.OverageRevenue AS Revenue,
           x.PlanRevenue + x.OverageRevenue - x.AiCostUsd AS Margin
    FROM (
        SELECT t.Id AS TenantId, t.Name AS TenantName, p.Code AS PlanCode, u.Reports, u.IncludedReports, u.OverageReports,
               ISNULL(g.Calls, 0) AS Calls, ISNULL(g.InputTokens, 0) AS InputTokens, ISNULL(g.OutputTokens, 0) AS OutputTokens,
               CONVERT(DECIMAL(19,2), ISNULL(g.CostUsd, 0)) AS AiCostUsd,
               IIF(p.IncludedAiReports > 0, p.MonthlyPrice, CONVERT(DECIMAL(19,2), 0)) AS PlanRevenue,
               u.OverageAmount AS OverageRevenue
        FROM admin.Tenant AS t
        JOIN admin.[Plan] AS p ON p.Id = t.PlanId
        CROSS APPLY admin.fn_PiloUsage(t.Id, @Month) AS u
        OUTER APPLY (SELECT COUNT(*) AS Calls, SUM(CONVERT(BIGINT, a.InputTokens)) AS InputTokens,
                            SUM(CONVERT(BIGINT, a.OutputTokens)) AS OutputTokens, SUM(a.CostUsd) AS CostUsd
                     FROM ai.Generation AS a WHERE a.TenantId = t.Id AND a.CreatedAt >= @From AND a.CreatedAt < @To) AS g
        WHERE p.IncludedAiReports > 0 OR g.Calls > 0
    ) AS x
    ORDER BY x.PlanRevenue + x.OverageRevenue - x.AiCostUsd;
END;
