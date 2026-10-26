-- Daily platform job (IsPlatformAdmin), before admin.usp_PlatformStatement_Generate on the 1st: applies waiting downgrades whose
-- EffectiveDate has come. Saved Pilo reports past the new limits stay readable; new saves are refused by usp_SavedReport_Save.
-- Returns how many were applied.
CREATE PROCEDURE admin.usp_PlanChange_ApplyDue
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Id INT, @T INT, @To INT, @Applied INT = 0;
    DECLARE due CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.Id, c.TenantId, c.ToPlanId FROM admin.TenantPlanChange AS c
        JOIN admin.Tenant AS t ON t.Id = c.TenantId
        WHERE c.Status = 'PENDING' AND c.EffectiveDate <= CAST(SYSUTCDATETIME() AS DATE)
        ORDER BY c.Id;
    OPEN due;
    FETCH NEXT FROM due INTO @Id, @T, @To;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC admin.usp_Tenant_ApplyPlan @TenantId = @T, @ToPlanId = @To, @Kind = 'DOWNGRADE', @PlanChangeId = @Id OUTPUT;
        SET @Applied += 1;
        FETCH NEXT FROM due INTO @Id, @T, @To;
    END;
    CLOSE due;
    DEALLOCATE due;

    SELECT @Applied AS Applied;
END;
