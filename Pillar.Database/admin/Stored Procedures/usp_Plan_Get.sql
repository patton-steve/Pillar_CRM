-- One plan for the back office plan editor (Pillar staff, handoff 26). Three result sets: the plan with today's terms; every
-- version (history and scheduled, newest first, with Status APPLIED / SCHEDULED / CANCELLED); the tenants on it.
CREATE PROCEDURE admin.usp_Plan_Get
    @PlanId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.[Plan] WHERE Id = @PlanId) THROW 52204, N'Unknown plan.', 1;
    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);

    SELECT p.Id AS PlanId, p.Code, p.Name, p.IsDefault, p.IsActive, p.IsPublic, p.SortOrder,
           pt.FeeRate, pt.PerInvoiceCap, pt.MonthlyMinimum, pt.FeePerHeadCap, pt.ExcludeExpensesFromFee, pt.MonthlyPrice,
           pt.IncludedSeats, pt.ExtraSeatPrice, pt.MaxSeats, pt.IncludedAiReports, pt.AiOveragePrice, pt.IncludedAiSearches,
           pt.EffectiveFrom AS TermsEffectiveFrom
    FROM admin.[Plan] AS p
    CROSS APPLY admin.fn_PlanTerms(p.Id, @Today) AS pt
    WHERE p.Id = @PlanId;

    SELECT v.Id AS PlanVersionId, v.EffectiveFrom,
           CASE WHEN v.CancelledAt IS NOT NULL THEN 'CANCELLED' WHEN v.EffectiveFrom > @Today THEN 'SCHEDULED' ELSE 'APPLIED' END AS Status,
           v.FeeRate, v.PerInvoiceCap, v.MonthlyMinimum, v.FeePerHeadCap, v.ExcludeExpensesFromFee, v.MonthlyPrice, v.IncludedSeats,
           v.ExtraSeatPrice, v.MaxSeats, v.IncludedAiReports, v.AiOveragePrice, v.IncludedAiSearches,
           v.Reason, v.CreatedAt, u.DisplayName AS CreatedByName, v.AppliedAt, v.CancelledAt
    FROM admin.PlanVersion AS v
    LEFT JOIN sec.AppUser AS u ON u.Id = v.CreatedBy
    WHERE v.PlanId = @PlanId
    ORDER BY v.EffectiveFrom DESC, v.Id DESC;

    SELECT t.Id AS TenantId, t.Name AS TenantName, t.Status
    FROM admin.Tenant AS t
    WHERE t.PlanId = @PlanId
    ORDER BY t.Name;
END;
