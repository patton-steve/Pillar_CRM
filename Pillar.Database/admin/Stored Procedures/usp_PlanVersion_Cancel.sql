-- Cancels a scheduled plan version before its date (Pillar staff, handoff 26). A reason is required and audited.
CREATE PROCEDURE admin.usp_PlanVersion_Cancel
    @PlanVersionId  INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @Code VARCHAR(20), @Summary NVARCHAR(400);
    BEGIN TRAN;
    UPDATE v SET CancelledAt = SYSUTCDATETIME(),
                 @Summary = CONCAT(N'Cancelled the ', CONVERT(CHAR(10), v.EffectiveFrom, 23), N' version of ', p.Code), @Code = p.Code
    FROM admin.PlanVersion AS v
    JOIN admin.[Plan] AS p ON p.Id = v.PlanId
    WHERE v.Id = @PlanVersionId AND v.CancelledAt IS NULL AND v.AppliedAt IS NULL AND v.EffectiveFrom > CAST(SYSUTCDATETIME() AS DATE);
    IF @@ROWCOUNT = 0 THROW 52606, N'Only a scheduled version (not yet in force) can be cancelled.', 1;
    EXEC admin.usp_PlatformAudit_Write @Action = 'PLAN_VERSION_CANCEL', @EntityType = 'PLAN', @EntityKey = @Code,
         @Summary = @Summary, @Reason = @Reason;
    COMMIT;
END;
