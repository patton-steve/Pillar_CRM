-- Back office > Announcements: adds (@AnnouncementId NULL) or edits an announcement; @IsActive = 0 takes it down. Pillar only.
CREATE PROCEDURE admin.usp_Announcement_Save
    @Title          NVARCHAR(200),
    @Body           NVARCHAR(2000) = NULL,
    @Severity       VARCHAR(12) = 'INFO',
    @LinkUrl        NVARCHAR(400) = NULL,
    @StartsAt       DATETIME2(0) = NULL,    -- default now
    @EndsAt         DATETIME2(0) = NULL,
    @IsActive       BIT = 1,
    @AnnouncementId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL THROW 52270, N'A title is required.', 1;

    IF @AnnouncementId IS NULL
    BEGIN
        INSERT INTO admin.Announcement (Title, Body, Severity, LinkUrl, StartsAt, EndsAt, IsActive)
        VALUES (@Title, @Body, @Severity, @LinkUrl, COALESCE(@StartsAt, SYSUTCDATETIME()), @EndsAt, @IsActive);
        SET @AnnouncementId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE admin.Announcement
        SET Title = @Title, Body = @Body, Severity = @Severity, LinkUrl = @LinkUrl, StartsAt = COALESCE(@StartsAt, StartsAt),
            EndsAt = @EndsAt, IsActive = @IsActive, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
        WHERE Id = @AnnouncementId;
        IF @@ROWCOUNT = 0 THROW 52270, N'Unknown announcement.', 1;
    END;
END;
