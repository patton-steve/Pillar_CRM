-- Announcements. @All = 0 (the app's banner): those showing now that the session user hasn't dismissed, MAINTENANCE first.
-- @All = 1 (back office, Pillar only): every announcement, newest first.
CREATE PROCEDURE admin.usp_Announcement_List
    @All BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @All = 1
    BEGIN
        IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
        SELECT a.Id, a.Title, a.Body, a.Severity, a.LinkUrl, a.StartsAt, a.EndsAt, a.IsActive, a.CreatedAt,
               (SELECT COUNT(*) FROM sec.UserAnnouncementDismissal AS d WHERE d.AnnouncementId = a.Id) AS Dismissals
        FROM admin.Announcement AS a
        ORDER BY a.Id DESC;
        RETURN;
    END;

    SELECT a.Id, a.Title, a.Body, a.Severity, a.LinkUrl, a.StartsAt, a.EndsAt
    FROM admin.Announcement AS a
    WHERE a.IsActive = 1 AND a.StartsAt <= @Now AND (a.EndsAt IS NULL OR a.EndsAt > @Now)
      AND NOT EXISTS (SELECT 1 FROM sec.UserAnnouncementDismissal AS d
                      WHERE d.TenantId = @TenantId AND d.AppUserId = @UserId AND d.AnnouncementId = a.Id)
    ORDER BY IIF(a.Severity = 'MAINTENANCE', 0, 1), a.StartsAt DESC;
END;
