-- Puts a notification in the bell of everyone who should hear about an event. Recipients come from
-- sec.fn_NotificationRecipients, or from @RecipientUserIds (JSON array of user ids) when the caller already knows them.
-- Skipped: the person who caused it (SESSION_CONTEXT UserId), users who can't sign in or aren't ACTIVE, and users who
-- turned off both channels (sec.fn_NotificationChannels). Someone who wants it by email only gets a row that is already
-- dismissed, with SendEmail = 1, for the email job. If a recipient already has an unread notification of the same type for the same record, it is
-- refreshed (new title, body and time) instead of piling up.
-- Database procs raise their own events (task created/assigned, mentions, task comments, budget alerts); the API calls
-- this after the other events: project created, task reassigned or status changed, timesheet submitted or sent back,
-- invoice paid, bill submitted for approval.
-- @ForTenantId (handoff 22): Pillar's procs (IsPlatformAdmin) raise into another tenant, e.g. a failed Pillar charge or a support reply.
CREATE PROCEDURE sec.usp_Notification_Raise
    @NotificationType   VARCHAR(40),
    @EntityType         VARCHAR(20),
    @EntityId           INT,
    @Title              NVARCHAR(200),
    @Body               NVARCHAR(1000) = NULL,
    @RecipientUserIds   NVARCHAR(MAX) = NULL,
    @Count              INT = NULL OUTPUT,
    @ForTenantId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @ActorId  INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @DefaultOn BIT;

    IF @ForTenantId IS NOT NULL AND ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 1
        SET @TenantId = @ForTenantId;
    IF @TenantId IS NULL THROW 51301, N'SESSION_CONTEXT TenantId is not set.', 1;
    SELECT @DefaultOn = DefaultOn FROM sec.NotificationType WHERE Code = @NotificationType;
    IF @DefaultOn IS NULL THROW 51302, N'Unknown notification type.', 1;
    IF @RecipientUserIds IS NOT NULL AND ISJSON(@RecipientUserIds) = 0
        THROW 51303, N'Recipients must be a JSON array of user ids.', 1;

    CREATE TABLE #to (AppUserId INT PRIMARY KEY, InAppOn BIT NULL, EmailOn BIT NULL);
    IF @RecipientUserIds IS NULL
        INSERT INTO #to (AppUserId)
        SELECT DISTINCT AppUserId FROM sec.fn_NotificationRecipients(@TenantId, @NotificationType, @EntityType, @EntityId)
        WHERE AppUserId IS NOT NULL;
    ELSE
        INSERT INTO #to (AppUserId)
        SELECT DISTINCT TRY_CONVERT(INT, value) FROM OPENJSON(@RecipientUserIds) WHERE TRY_CONVERT(INT, value) IS NOT NULL;

    DELETE x FROM #to AS x
    WHERE x.AppUserId = @ActorId
       OR NOT EXISTS (SELECT 1 FROM sec.AppUser AS u
                      WHERE u.TenantId = @TenantId AND u.Id = x.AppUserId AND u.Status = 'ACTIVE' AND u.CanLogin = 1);

    UPDATE x SET InAppOn = c.InAppOn, EmailOn = c.EmailOn
    FROM #to AS x
    CROSS APPLY sec.fn_NotificationChannels(@TenantId, x.AppUserId, @NotificationType) AS c;
    DELETE FROM #to WHERE ISNULL(InAppOn, 0) = 0 AND ISNULL(EmailOn, 0) = 0;

    BEGIN TRAN;

    UPDATE n SET Title = @Title, Body = @Body, ActorUserId = @ActorId, CreatedAt = @Now
    FROM sec.Notification AS n
    JOIN #to AS x ON x.AppUserId = n.AppUserId AND x.InAppOn = 1
    WHERE n.TenantId = @TenantId AND n.NotificationType = @NotificationType AND n.EntityType = @EntityType
      AND n.EntityId = @EntityId AND n.ReadAt IS NULL AND n.DismissedAt IS NULL;

    INSERT INTO sec.Notification (TenantId, AppUserId, NotificationType, Title, Body, EntityType, EntityId, ActorUserId, CreatedAt,
                                  SendEmail, DismissedAt)
    SELECT @TenantId, x.AppUserId, @NotificationType, @Title, @Body, @EntityType, @EntityId, @ActorId, @Now,
           ISNULL(x.EmailOn, 0), IIF(x.InAppOn = 1, NULL, @Now)
    FROM #to AS x
    WHERE NOT EXISTS (SELECT 1 FROM sec.Notification AS n
                      WHERE n.TenantId = @TenantId AND n.AppUserId = x.AppUserId AND n.NotificationType = @NotificationType
                        AND n.EntityType = @EntityType AND n.EntityId = @EntityId AND n.ReadAt IS NULL AND n.DismissedAt IS NULL
                        AND x.InAppOn = 1);

    COMMIT;
    SELECT @Count = COUNT(*) FROM #to;
END;
