-- The tenant cancels its waiting downgrade (billing.manage). Audited.
CREATE PROCEDURE admin.usp_PlanChange_Cancel
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
        THROW 52221, N'Only people who manage Pillar billing can change the plan.', 1;

    BEGIN TRAN;
    UPDATE admin.TenantPlanChange SET Status = 'CANCELLED', CancelledAt = SYSUTCDATETIME() WHERE TenantId = @TenantId AND Status = 'PENDING';
    IF @@ROWCOUNT = 0 THROW 52225, N'There is no plan change waiting.', 1;
    EXEC admin.usp_Audit_Write @Area = 'billing', @EntityType = 'PLAN', @Action = 'UPDATE', @Summary = N'Cancelled the waiting downgrade';
    COMMIT;
END;
