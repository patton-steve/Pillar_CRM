-- The tenant changes its plan (Admin > Billing & plan; billing.manage; ACTIVE accounts only). Steve 2026-10-22:
--   upgrade (higher monthly price)  applied now; the statement prorates both plans by day
--   downgrade                       waits as PENDING until the 1st of next month (admin.usp_PlanChange_ApplyDue applies it);
--                                   refused while admin.fn_PlanChangeIssues has a BLOCK (too many saved Pilo reports)
-- A new request replaces a waiting downgrade. Audited.
CREATE PROCEDURE admin.usp_PlanChange_Request
    @ToPlanCode     VARCHAR(20),
    @PlanChangeId   INT = NULL OUTPUT,
    @Applied        BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @ToPlanId INT, @FromPlanId INT, @FromPrice DECIMAL(19,2), @ToPrice DECIMAL(19,2), @Status VARCHAR(15),
            @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Summary NVARCHAR(400), @Change NVARCHAR(MAX), @FromCode VARCHAR(20);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
        THROW 52221, N'Only people who manage Pillar billing can change the plan.', 1;
    SELECT @ToPlanId = Id, @ToPrice = MonthlyPrice FROM admin.[Plan] WHERE Code = @ToPlanCode AND IsActive = 1;
    IF @ToPlanId IS NULL THROW 52204, N'Unknown plan.', 1;

    BEGIN TRAN;
    SELECT @FromPlanId = t.PlanId, @FromPrice = p.MonthlyPrice, @FromCode = p.Code, @Status = t.Status
    FROM admin.Tenant AS t WITH (UPDLOCK) JOIN admin.[Plan] AS p ON p.Id = t.PlanId
    WHERE t.Id = @TenantId;
    IF @Status <> 'ACTIVE' THROW 52222, N'The plan can be changed once the account is active.', 1;
    IF @FromPlanId = @ToPlanId THROW 52223, N'The account is already on that plan.', 1;

    SET @Change = (SELECT N'Plan' AS field, @FromCode AS [from], @ToPlanCode AS [to] FOR JSON PATH);
    IF @ToPrice > @FromPrice
    BEGIN
        EXEC admin.usp_Tenant_ApplyPlan @TenantId = @TenantId, @ToPlanId = @ToPlanId, @Kind = 'UPGRADE', @PlanChangeId = @PlanChangeId OUTPUT;
        SET @Applied = 1;
        SET @Summary = CONCAT(N'Upgraded to ', @ToPlanCode);
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM admin.fn_PlanChangeIssues(@TenantId, @ToPlanId) WHERE Severity = 'BLOCK')
            THROW 52224, N'Remove the items listed for the new plan before downgrading.', 1;
        UPDATE admin.TenantPlanChange SET Status = 'CANCELLED', CancelledAt = SYSUTCDATETIME() WHERE TenantId = @TenantId AND Status = 'PENDING';
        INSERT INTO admin.TenantPlanChange (TenantId, FromPlanId, ToPlanId, Kind, Status, EffectiveDate)
        VALUES (@TenantId, @FromPlanId, @ToPlanId, 'DOWNGRADE', 'PENDING', DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1)));
        SET @PlanChangeId = SCOPE_IDENTITY();
        SET @Applied = 0;
        SET @Summary = CONCAT(N'Downgrade to ', @ToPlanCode, N' requested for the 1st of next month');
    END;

    EXEC admin.usp_Audit_Write @Area = 'billing', @EntityType = 'PLAN', @EntityKey = @ToPlanCode, @Action = 'UPDATE',
         @Summary = @Summary, @ChangeJson = @Change;
    COMMIT;
END;
