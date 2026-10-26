-- The signed-in user's notification settings table: every type, grouped by Category, with what is on for them per channel
-- and which channels the company locked on (show those switched on and disabled). Email is stored now and shown as
-- "Coming soon" until sending exists. Digest and quiet hours are user preferences (notify.digest, notify.quietStart,
-- notify.quietEnd in admin.UserPreference).
CREATE PROCEDURE sec.usp_NotificationSetting_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51304, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT t.Code, t.Name, t.Description, t.Category, t.DefaultOn, t.DefaultEmailOn,
           c.InAppOn AS IsOn, c.EmailOn, c.InAppLocked, c.EmailLocked, t.ActionKind, t.SortOrder
    FROM sec.NotificationType AS t
    CROSS APPLY sec.fn_NotificationChannels(@TenantId, @UserId, t.Code) AS c
    ORDER BY t.SortOrder;
END;
