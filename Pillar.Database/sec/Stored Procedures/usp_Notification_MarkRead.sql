-- Marks the signed-in user's notifications read (opening one, or "mark all read"), or dismisses them from the bell.
-- @NotificationIds is a JSON array of ids; NULL = all of the user's notifications.
CREATE PROCEDURE sec.usp_Notification_MarkRead
    @NotificationIds    NVARCHAR(MAX) = NULL,
    @Dismiss            BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51304, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF @NotificationIds IS NOT NULL AND ISJSON(@NotificationIds) = 0
        THROW 51305, N'Notification ids must be a JSON array.', 1;

    UPDATE n
    SET ReadAt = COALESCE(n.ReadAt, @Now),
        DismissedAt = CASE WHEN @Dismiss = 1 THEN COALESCE(n.DismissedAt, @Now) ELSE n.DismissedAt END
    FROM sec.Notification AS n
    WHERE n.TenantId = @TenantId AND n.AppUserId = @UserId AND n.DismissedAt IS NULL
      AND (@NotificationIds IS NULL
           OR n.Id IN (SELECT TRY_CONVERT(BIGINT, value) FROM OPENJSON(@NotificationIds)));
END;
