-- Appends one row to Pillar's own audit trail (admin.PlatformAudit). Called by every back-office proc after its change.
CREATE PROCEDURE admin.usp_PlatformAudit_Write
    @Action         VARCHAR(30),
    @TenantId       INT = NULL,
    @EntityType     VARCHAR(30) = NULL,
    @EntityKey      NVARCHAR(100) = NULL,
    @Summary        NVARCHAR(400) = NULL,
    @Reason         NVARCHAR(500) = NULL,
    @ChangeJson     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO admin.PlatformAudit (TenantId, Action, EntityType, EntityKey, Summary, Reason, ChangeJson)
    VALUES (@TenantId, @Action, @EntityType, @EntityKey, @Summary, @Reason, @ChangeJson);
END;
