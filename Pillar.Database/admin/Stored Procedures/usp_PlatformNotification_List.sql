-- Pillar's back-office inbox, newest first. Also returns the unread count (second result set) for the badge.
CREATE PROCEDURE admin.usp_PlatformNotification_List
    @UnreadOnly BIT = 0,
    @BeforeId   INT = NULL,
    @Top        INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    SELECT TOP (@Top) n.Id, n.Kind, n.TenantId, t.Name AS TenantName, n.EntityType, n.EntityId, n.Title, n.Body, n.DataJson,
           n.CreatedAt, n.ReadAt, n.EmailedAt
    FROM admin.PlatformNotification AS n
    LEFT JOIN admin.Tenant AS t ON t.Id = n.TenantId
    WHERE (@UnreadOnly = 0 OR n.ReadAt IS NULL) AND (@BeforeId IS NULL OR n.Id < @BeforeId)
    ORDER BY n.Id DESC;

    SELECT COUNT(*) AS UnreadCount FROM admin.PlatformNotification WHERE ReadAt IS NULL;
END;
