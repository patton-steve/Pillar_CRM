-- Appends one row to admin.AuditLog for the session tenant and user. Called by every admin proc after its change, and by the
-- API for admin writes it makes directly. Silent when there is no tenant in session (post-deploy seeds aren't audited).
-- @TenantId (handoff 22) writes to another tenant's log; only Pillar staff (IsPlatformAdmin) may, e.g. for back-office changes.
CREATE PROCEDURE admin.usp_Audit_Write
    @Area           VARCHAR(30),
    @EntityType     VARCHAR(30),
    @EntityKey      NVARCHAR(100) = NULL,
    @Action         VARCHAR(10),
    @Summary        NVARCHAR(400) = NULL,
    @ChangeJson     NVARCHAR(MAX) = NULL,
    @TenantId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Target INT = CASE WHEN @TenantId IS NOT NULL AND ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 1
                               THEN @TenantId ELSE CONVERT(INT, SESSION_CONTEXT(N'TenantId')) END;
    IF @Target IS NULL RETURN;

    INSERT INTO admin.AuditLog (TenantId, Area, EntityType, EntityKey, Action, Summary, ChangeJson)
    VALUES (@Target, @Area, @EntityType, @EntityKey, @Action, @Summary, @ChangeJson);
END;
