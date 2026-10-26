-- Marks one inbox item (@NotificationId) or all of them (@All = 1) read.
CREATE PROCEDURE admin.usp_PlatformNotification_MarkRead
    @NotificationId INT = NULL,
    @All            BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    UPDATE admin.PlatformNotification
    SET ReadAt = SYSUTCDATETIME(), ReadBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
    WHERE ReadAt IS NULL AND (@All = 1 OR Id = @NotificationId);
END;
