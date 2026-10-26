-- How one person receives one notification type: user choice -> tenant default -> Pillar default, per channel, except a
-- channel the tenant locked on, which is always on. Usage:
--   SELECT InAppOn, EmailOn, InAppLocked, EmailLocked FROM sec.fn_NotificationChannels(@TenantId, @UserId, 'MENTIONED');
CREATE FUNCTION sec.fn_NotificationChannels (@TenantId INT, @AppUserId INT, @NotificationType VARCHAR(40))
RETURNS TABLE
AS
RETURN
    SELECT CONVERT(BIT, CASE WHEN ti.IsLocked = 1 THEN 1 ELSE COALESCE(u.IsOn, ti.IsOn, nt.DefaultOn) END) AS InAppOn,
           CONVERT(BIT, CASE WHEN te.IsLocked = 1 THEN 1 ELSE COALESCE(u.EmailOn, te.IsOn, nt.DefaultEmailOn) END) AS EmailOn,
           CONVERT(BIT, ISNULL(ti.IsLocked, 0)) AS InAppLocked,
           CONVERT(BIT, ISNULL(te.IsLocked, 0)) AS EmailLocked
    FROM sec.NotificationType AS nt
    LEFT JOIN admin.TenantNotificationDefault AS ti
        ON ti.TenantId = @TenantId AND ti.NotificationType = nt.Code AND ti.Channel = 'IN_APP'
    LEFT JOIN admin.TenantNotificationDefault AS te
        ON te.TenantId = @TenantId AND te.NotificationType = nt.Code AND te.Channel = 'EMAIL'
    LEFT JOIN sec.UserNotificationSetting AS u
        ON u.TenantId = @TenantId AND u.AppUserId = @AppUserId AND u.NotificationType = nt.Code
    WHERE nt.Code = @NotificationType;
