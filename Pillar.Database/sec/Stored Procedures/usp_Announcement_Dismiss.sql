-- The session user closes an announcement banner; it stays hidden for them.
CREATE PROCEDURE sec.usp_Announcement_Dismiss
    @AnnouncementId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    INSERT INTO sec.UserAnnouncementDismissal (TenantId, AppUserId, AnnouncementId)
    SELECT @TenantId, @UserId, a.Id FROM admin.Announcement AS a
    WHERE a.Id = @AnnouncementId
      AND NOT EXISTS (SELECT 1 FROM sec.UserAnnouncementDismissal AS d
                      WHERE d.TenantId = @TenantId AND d.AppUserId = @UserId AND d.AnnouncementId = a.Id);
END;
