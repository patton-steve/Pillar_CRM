-- A tenant's Ask Pilo searches in the month starting @PeriodStart (UTC): Searches (successful ai.Generation rows with Feature
-- ASK_SEARCH), IncludedSearches (the plan's IncludedAiSearches, or Pilo.MonthlySearchesOverride) and Remaining. A hard limit:
-- the API refuses a search when Remaining is 0; there is no overage. Uses the tenant's current plan.
CREATE FUNCTION admin.fn_PiloSearchUsage (@TenantId INT, @PeriodStart DATE)
RETURNS TABLE
AS
RETURN
    SELECT u.Searches, u.IncludedSearches,
           CASE WHEN u.Searches >= u.IncludedSearches THEN 0 ELSE u.IncludedSearches - u.Searches END AS Remaining
    FROM (
        SELECT (SELECT COUNT(*) FROM ai.Generation AS g
                WHERE g.TenantId = t.Id AND g.Feature = 'ASK_SEARCH' AND g.Succeeded = 1
                  AND g.CreatedAt >= CONVERT(DATETIME2(0), @PeriodStart)
                  AND g.CreatedAt < DATEADD(MONTH, 1, CONVERT(DATETIME2(0), @PeriodStart))) AS Searches,
               COALESCE(TRY_CONVERT(INT, so.Value), p.IncludedAiSearches) AS IncludedSearches
        FROM admin.Tenant AS t
        JOIN admin.[Plan] AS p ON p.Id = t.PlanId
        OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Pilo.MonthlySearchesOverride') AS so
        WHERE t.Id = @TenantId
    ) AS u;
