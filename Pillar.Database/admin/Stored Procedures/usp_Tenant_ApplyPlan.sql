-- Internal: moves a tenant to another plan now and records it in admin.TenantPlanChange (APPLIED, effective today, UTC).
-- Callers check who may do it: admin.usp_Tenant_Approve / _SetPlan (Pillar), admin.usp_PlanChange_Request (upgrades) and
-- admin.usp_PlanChange_ApplyDue (downgrades that came due, which pass @PlanChangeId instead of inserting a row).
-- Waiting downgrades are cancelled when another change is applied.
CREATE PROCEDURE admin.usp_Tenant_ApplyPlan
    @TenantId       INT,
    @ToPlanId       INT,
    @Kind           VARCHAR(10),
    @Note           NVARCHAR(500) = NULL,
    @PlanChangeId   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FromPlanId INT, @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
    SELECT @FromPlanId = PlanId FROM admin.Tenant WITH (UPDLOCK) WHERE Id = @TenantId;
    IF @FromPlanId IS NULL THROW 52202, N'Unknown tenant.', 1;

    IF @FromPlanId <> @ToPlanId
    BEGIN
        IF @PlanChangeId IS NULL
        BEGIN
            UPDATE admin.TenantPlanChange SET Status = 'CANCELLED', CancelledAt = @Now WHERE TenantId = @TenantId AND Status = 'PENDING';
            INSERT INTO admin.TenantPlanChange (TenantId, FromPlanId, ToPlanId, Kind, Status, EffectiveDate, AppliedAt, Note)
            VALUES (@TenantId, @FromPlanId, @ToPlanId, @Kind, 'APPLIED', CAST(@Now AS DATE), @Now, @Note);
            SET @PlanChangeId = SCOPE_IDENTITY();
        END
        ELSE
            UPDATE admin.TenantPlanChange SET Status = 'APPLIED', AppliedAt = @Now, FromPlanId = @FromPlanId
            WHERE TenantId = @TenantId AND Id = @PlanChangeId;

        UPDATE admin.Tenant SET PlanId = @ToPlanId, ModifiedAt = @Now, ModifiedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
        WHERE Id = @TenantId;
    END;
    ELSE IF @PlanChangeId IS NOT NULL
        -- already on that plan: the waiting change has nothing left to do
        UPDATE admin.TenantPlanChange SET Status = 'CANCELLED', CancelledAt = @Now WHERE TenantId = @TenantId AND Id = @PlanChangeId;
    COMMIT;
END;
