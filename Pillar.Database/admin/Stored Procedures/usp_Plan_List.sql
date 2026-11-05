-- Plans with today's terms (handoff 26). Pillar staff see every plan with its tenant count and next scheduled version
-- (back office > Plans); anyone else sees the public, active plans plus the plan their company is on (sign-up and Billing & plan).
CREATE PROCEDURE admin.usp_Plan_List
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsStaff BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @Today DATE = CAST(SYSUTCDATETIME() AS DATE),
            @CurrentPlanId INT;
    SELECT @CurrentPlanId = PlanId FROM admin.Tenant WHERE Id = @TenantId;

    SELECT p.Id AS PlanId, p.Code, p.Name, p.IsDefault, p.IsActive, p.IsPublic, p.SortOrder,
           pt.FeeRate, pt.PerInvoiceCap, pt.MonthlyMinimum, pt.FeePerHeadCap, pt.ExcludeExpensesFromFee, pt.MonthlyPrice,
           pt.IncludedSeats, pt.ExtraSeatPrice, pt.MaxSeats, pt.IncludedAiReports, pt.AiOveragePrice, pt.IncludedAiSearches,
           CASE WHEN @IsStaff = 1 THEN (SELECT COUNT(*) FROM admin.Tenant AS t WHERE t.PlanId = p.Id
                                        AND t.Status <> 'CANCELLED' AND t.Status <> 'DECLINED') END AS TenantCount,
           nv.EffectiveFrom AS NextVersionDate,
           CONVERT(BIT, IIF(p.Id = @CurrentPlanId, 1, 0)) AS IsCurrentPlan
    FROM admin.[Plan] AS p
    CROSS APPLY admin.fn_PlanTerms(p.Id, @Today) AS pt
    OUTER APPLY (SELECT TOP (1) v.EffectiveFrom FROM admin.PlanVersion AS v
                 WHERE v.PlanId = p.Id AND v.CancelledAt IS NULL AND v.EffectiveFrom > @Today ORDER BY v.EffectiveFrom) AS nv
    WHERE (@IsStaff = 1 AND (@IncludeInactive = 1 OR p.IsActive = 1))
       OR (@IsStaff = 0 AND ((p.IsPublic = 1 AND p.IsActive = 1) OR p.Id = @CurrentPlanId))
    ORDER BY p.SortOrder, p.Code;
END;
