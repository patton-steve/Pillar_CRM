-- Settings > Notification defaults: every type with Pillar's default, the company's default and lock per channel.
-- Needs settings.notifications.
CREATE PROCEDURE admin.usp_TenantNotificationDefault_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51741, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.notifications'))
        THROW 51742, N'You need permission to change notification defaults.', 1;

    SELECT t.Code, t.Name, t.Description, t.Category, t.SortOrder,
           t.DefaultOn AS PillarInAppOn, COALESCE(i.IsOn, t.DefaultOn) AS InAppOn, CONVERT(BIT, ISNULL(i.IsLocked, 0)) AS InAppLocked,
           t.DefaultEmailOn AS PillarEmailOn, COALESCE(e.IsOn, t.DefaultEmailOn) AS EmailOn, CONVERT(BIT, ISNULL(e.IsLocked, 0)) AS EmailLocked
    FROM sec.NotificationType AS t
    LEFT JOIN admin.TenantNotificationDefault AS i ON i.TenantId = @TenantId AND i.NotificationType = t.Code AND i.Channel = 'IN_APP'
    LEFT JOIN admin.TenantNotificationDefault AS e ON e.TenantId = @TenantId AND e.NotificationType = t.Code AND e.Channel = 'EMAIL'
    ORDER BY t.SortOrder;
END;
