-- Removes notifications from the signed-in user's bell: one (@NotificationId) or all of them (@All = 1).
-- Dismissed rows are also marked read. Same as usp_Notification_MarkRead with @Dismiss = 1.
CREATE PROCEDURE sec.usp_Notification_Dismiss
    @NotificationId BIGINT = NULL,
    @All            BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51304, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF @NotificationId IS NULL AND ISNULL(@All, 0) = 0 THROW 51305, N'Pass a notification or @All = 1.', 1;

    UPDATE sec.Notification
    SET ReadAt = COALESCE(ReadAt, @Now), DismissedAt = @Now
    WHERE TenantId = @TenantId AND AppUserId = @UserId AND DismissedAt IS NULL
      AND (@All = 1 OR Id = @NotificationId);
END;
