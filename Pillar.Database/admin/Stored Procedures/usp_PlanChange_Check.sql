-- Admin > Billing & plan, before a plan change: what moving to @ToPlanCode means. First result set: the change (current and new
-- plan, price difference, IsUpgrade, EffectiveDate: today for an upgrade, the 1st of next month for a downgrade). Second: the
-- issues from admin.fn_PlanChangeIssues (BLOCK rows must be cleared first). Needs billing.manage.
CREATE PROCEDURE admin.usp_PlanChange_Check
    @ToPlanCode VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @ToPlanId INT, @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    IF @TenantId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
       AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
        THROW 52221, N'Only people who manage Pillar billing can change the plan.', 1;
    SELECT @ToPlanId = Id FROM admin.[Plan] WHERE Code = @ToPlanCode AND IsActive = 1;
    IF @ToPlanId IS NULL THROW 52204, N'Unknown plan.', 1;

    SELECT f.Code AS FromPlanCode, f.Name AS FromPlanName, f.MonthlyPrice AS FromPrice,
           p.Code AS ToPlanCode, p.Name AS ToPlanName, p.MonthlyPrice AS ToPrice,
           CONVERT(BIT, IIF(p.MonthlyPrice > f.MonthlyPrice, 1, 0)) AS IsUpgrade,
           IIF(p.MonthlyPrice > f.MonthlyPrice, @Today, DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1))) AS EffectiveDate
    FROM admin.Tenant AS t
    JOIN admin.[Plan] AS f ON f.Id = t.PlanId
    JOIN admin.[Plan] AS p ON p.Id = @ToPlanId
    WHERE t.Id = @TenantId;

    SELECT IssueCode, Severity, AppUserId, CurrentCount, AllowedCount, Message
    FROM admin.fn_PlanChangeIssues(@TenantId, @ToPlanId);
END;
