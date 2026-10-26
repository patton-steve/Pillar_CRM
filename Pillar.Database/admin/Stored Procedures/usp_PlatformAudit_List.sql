-- Pillar's audit trail for the back office, newest first, optionally for one tenant. Pages with @BeforeId.
CREATE PROCEDURE admin.usp_PlatformAudit_List
    @TenantId   INT = NULL,
    @Action     VARCHAR(30) = NULL,
    @BeforeId   BIGINT = NULL,
    @Top        INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    SELECT TOP (@Top) a.Id, a.OccurredAt, a.ActorUserId, u.DisplayName AS ActorName, a.TenantId, t.Name AS TenantName,
           a.Action, a.EntityType, a.EntityKey, a.Summary, a.Reason, a.ChangeJson, a.IpAddress
    FROM admin.PlatformAudit AS a
    LEFT JOIN admin.Tenant AS t ON t.Id = a.TenantId
    LEFT JOIN sec.AppUser AS u ON u.Id = a.ActorUserId
    WHERE (@TenantId IS NULL OR a.TenantId = @TenantId)
      AND (@Action IS NULL OR a.Action = @Action)
      AND (@BeforeId IS NULL OR a.Id < @BeforeId)
    ORDER BY a.Id DESC;
END;
