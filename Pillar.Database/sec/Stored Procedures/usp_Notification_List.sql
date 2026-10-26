-- The signed-in user's bell, newest first, without dismissed rows. Page with @BeforeId (the last Id already shown).
-- @UnreadCount is the badge number. ActionKind says which quick actions to show (APPROVE_TIMESHEET, REPLY).
CREATE PROCEDURE sec.usp_Notification_List
    @UnreadOnly     BIT = 0,
    @Top            INT = 30,
    @BeforeId       BIGINT = NULL,
    @UnreadCount    INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51304, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT @UnreadCount = COUNT(*) FROM sec.Notification
    WHERE TenantId = @TenantId AND AppUserId = @UserId AND ReadAt IS NULL AND DismissedAt IS NULL;

    SELECT TOP (@Top) n.Id, n.NotificationType, t.Name AS TypeName, n.Title, n.Body, n.EntityType, n.EntityId,
           n.ActorUserId, a.DisplayName AS ActorName, n.CreatedAt, n.ReadAt, t.ActionKind
    FROM sec.Notification AS n
    JOIN sec.NotificationType AS t ON t.Code = n.NotificationType
    LEFT JOIN sec.AppUser AS a ON a.TenantId = n.TenantId AND a.Id = n.ActorUserId
    WHERE n.TenantId = @TenantId AND n.AppUserId = @UserId AND n.DismissedAt IS NULL
      AND (@UnreadOnly = 0 OR n.ReadAt IS NULL) AND (@BeforeId IS NULL OR n.Id < @BeforeId)
    ORDER BY n.Id DESC;
END;
