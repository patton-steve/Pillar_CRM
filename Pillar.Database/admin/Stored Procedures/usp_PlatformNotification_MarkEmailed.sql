-- The API's email job: returns the inbox items still to email and the platform admins to send them to (@NotificationId NULL),
-- or marks one item emailed (@NotificationId set).
CREATE PROCEDURE admin.usp_PlatformNotification_MarkEmailed
    @NotificationId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    IF @NotificationId IS NOT NULL
    BEGIN
        UPDATE admin.PlatformNotification SET EmailedAt = SYSUTCDATETIME() WHERE Id = @NotificationId AND EmailedAt IS NULL;
        RETURN;
    END;

    SELECT n.Id, n.Kind, n.TenantId, t.Name AS TenantName, n.Title, n.Body, n.DataJson, n.CreatedAt
    FROM admin.PlatformNotification AS n
    LEFT JOIN admin.Tenant AS t ON t.Id = n.TenantId
    WHERE n.SendEmail = 1 AND n.EmailedAt IS NULL
    ORDER BY n.Id;

    SELECT u.Email, u.DisplayName
    FROM sec.AppUser AS u
    WHERE u.IsPlatformAdmin = 1 AND u.CanLogin = 1 AND u.Status = 'ACTIVE';
END;
