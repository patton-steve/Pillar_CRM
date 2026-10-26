-- Avatar for anyone in the session tenant: the kind, emote, colors and initials, plus the photo bytes when AvatarKind = PHOTO.
-- The API caches the image by AppUserId + PhotoUpdatedAt.
CREATE PROCEDURE sec.usp_UserAvatar_Get
    @AppUserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId'));
    IF @TenantId IS NULL THROW 51713, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT u.Id AS AppUserId, u.AvatarKind, u.AvatarPiloEmote, u.AvatarPrimaryColor, u.AvatarSecondaryColor,
           CONCAT(LEFT(u.FirstName, 1), LEFT(u.LastName, 1)) AS Initials,
           a.ContentType, IIF(u.AvatarKind = 'PHOTO', a.Bytes, NULL) AS Photo, a.UpdatedAt AS PhotoUpdatedAt
    FROM sec.AppUser AS u
    LEFT JOIN sec.UserAvatar AS a ON a.TenantId = u.TenantId AND a.AppUserId = u.Id
    WHERE u.TenantId = @TenantId AND u.Id = @AppUserId;
END;
