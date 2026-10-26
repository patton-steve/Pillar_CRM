-- Adds a note to a client (@NoteId NULL) or edits one (author only). @NoteTypeId NULL = the tenant's default note type;
-- @OccurredAt NULL = now. @ContactId ties the note to one of the client's contacts. @Body is sanitized HTML from the API.
-- @MentionUserIds is a JSON array of user ids @mentioned in the body; newly mentioned people get MENTIONED.
-- @Delete = 1 removes the note (soft delete, author only). Needs client.edit.
CREATE PROCEDURE crm.usp_ClientNote_Save
    @NoteId             INT = NULL OUTPUT,
    @ClientId           INT,
    @Body               NVARCHAR(MAX) = NULL,
    @NoteTypeId         INT = NULL,
    @ContactId          INT = NULL,
    @Subject            NVARCHAR(200) = NULL,
    @OccurredAt         DATETIME2(0) = NULL,
    @MentionUserIds     NVARCHAR(MAX) = NULL,
    @Delete             BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @ClientName NVARCHAR(200), @Title NVARCHAR(200), @To NVARCHAR(MAX);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51311, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'client.edit'))
        THROW 51321, N'You don''t have permission to add client notes.', 1;
    SELECT @ClientName = Name FROM crm.Client WHERE TenantId = @TenantId AND Id = @ClientId AND DeletedAt IS NULL;
    IF @ClientName IS NULL THROW 51322, N'Client not found.', 1;
    IF @NoteId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.ClientNote WHERE TenantId = @TenantId AND Id = @NoteId
                                           AND ClientId = @ClientId AND AuthorUserId = @UserId AND DeletedAt IS NULL)
        THROW 51323, N'You can only change your own notes.', 1;

    IF @Delete = 1
    BEGIN
        UPDATE crm.ClientNote SET DeletedAt = @Now WHERE TenantId = @TenantId AND Id = @NoteId;
        RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL THROW 51324, N'A note can''t be empty.', 1;
    IF @MentionUserIds IS NOT NULL AND ISJSON(@MentionUserIds) = 0 THROW 51314, N'Mentions must be a JSON array of user ids.', 1;
    SET @NoteTypeId = COALESCE(@NoteTypeId,
        (SELECT TOP (1) Id FROM lkp.NoteType WHERE TenantId = @TenantId AND IsActive = 1 ORDER BY IsDefault DESC, SortOrder, Id));

    CREATE TABLE #m (AppUserId INT PRIMARY KEY, IsNew BIT NOT NULL DEFAULT (1));
    INSERT INTO #m (AppUserId)
    SELECT DISTINCT u.Id
    FROM OPENJSON(ISNULL(@MentionUserIds, N'[]')) AS j
    JOIN sec.AppUser AS u ON u.TenantId = @TenantId AND u.Id = TRY_CONVERT(INT, j.value);

    BEGIN TRAN;

    IF @NoteId IS NULL
    BEGIN
        INSERT INTO crm.ClientNote (TenantId, ClientId, ContactId, NoteTypeId, Subject, Body, OccurredAt, AuthorUserId)
        VALUES (@TenantId, @ClientId, @ContactId, @NoteTypeId, @Subject, @Body, COALESCE(@OccurredAt, @Now), @UserId);
        SET @NoteId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE crm.ClientNote
        SET ContactId = @ContactId, NoteTypeId = @NoteTypeId, Subject = @Subject, Body = @Body,
            OccurredAt = COALESCE(@OccurredAt, OccurredAt), EditedAt = @Now
        WHERE TenantId = @TenantId AND Id = @NoteId;
        UPDATE m SET IsNew = 0 FROM #m AS m
        WHERE EXISTS (SELECT 1 FROM crm.ClientNoteMention AS x WHERE x.TenantId = @TenantId AND x.NoteId = @NoteId AND x.AppUserId = m.AppUserId);
        DELETE x FROM crm.ClientNoteMention AS x
        WHERE x.TenantId = @TenantId AND x.NoteId = @NoteId AND NOT EXISTS (SELECT 1 FROM #m AS m WHERE m.AppUserId = x.AppUserId);
    END;

    INSERT INTO crm.ClientNoteMention (TenantId, NoteId, AppUserId)
    SELECT @TenantId, @NoteId, AppUserId FROM #m WHERE IsNew = 1;

    IF EXISTS (SELECT 1 FROM #m WHERE IsNew = 1)
    BEGIN
        SELECT @Title = LEFT(CONCAT(DisplayName, N' mentioned you in a note on ', @ClientName), 200)
        FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @UserId;
        SELECT @To = CONCAT(N'[', STRING_AGG(CONVERT(VARCHAR(12), AppUserId), ','), N']') FROM #m WHERE IsNew = 1;
        EXEC sec.usp_Notification_Raise @NotificationType = 'MENTIONED', @EntityType = 'NOTE', @EntityId = @NoteId,
             @Title = @Title, @RecipientUserIds = @To;
    END;

    COMMIT;
END;
