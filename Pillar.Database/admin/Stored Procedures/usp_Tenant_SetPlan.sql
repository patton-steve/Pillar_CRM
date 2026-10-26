-- Pillar moves a tenant to another plan now (back office), with a reason. Recorded as a PLATFORM plan change, so the next
-- statement prorates it; a waiting downgrade is cancelled.
CREATE PROCEDURE admin.usp_Tenant_SetPlan
    @TenantId   INT,
    @PlanCode   VARCHAR(20),
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @PlanId INT, @Old VARCHAR(20), @Summary NVARCHAR(400), @Change NVARCHAR(MAX), @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @TenantId);
    SELECT @PlanId = Id FROM admin.[Plan] WHERE Code = @PlanCode AND IsActive = 1;
    IF @PlanId IS NULL THROW 52204, N'Unknown plan.', 1;
    SELECT @Old = p.Code FROM admin.Tenant AS t JOIN admin.[Plan] AS p ON p.Id = t.PlanId WHERE t.Id = @TenantId;
    IF @Old IS NULL THROW 52202, N'Unknown tenant.', 1;
    IF @Old = @PlanCode THROW 52223, N'The account is already on that plan.', 1;

    BEGIN TRAN;
    EXEC admin.usp_Tenant_ApplyPlan @TenantId = @TenantId, @ToPlanId = @PlanId, @Kind = 'PLATFORM', @Note = @Reason;
    SET @Summary = CONCAT(N'Plan ', @Old, N' to ', @PlanCode);
    SET @Change = (SELECT N'Plan' AS field, @Old AS [from], @PlanCode AS [to] FOR JSON PATH);
    EXEC admin.usp_PlatformAudit_Write @Action = 'SET_PLAN', @TenantId = @TenantId, @EntityType = 'TENANT', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    EXEC admin.usp_Audit_Write @Area = 'billing', @EntityType = 'PLAN', @EntityKey = @PlanCode, @Action = 'UPDATE',
         @Summary = @Summary, @ChangeJson = @Change, @TenantId = @TenantId;
    COMMIT;
END;
