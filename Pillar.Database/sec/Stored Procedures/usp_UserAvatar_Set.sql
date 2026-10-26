-- My profile picture: initials (default), a Pilo emote in my own colors, or an uploaded photo.
--   @AvatarKind INITIALS | PILO (needs @PiloEmote; colors optional, #RRGGBB) | PHOTO (needs @Photo unless one is stored)
-- @Photo is the browser's square crop: PNG or JPEG by file signature, 256 KB max. Saving another kind keeps the photo so the
-- person can switch back; @RemovePhoto = 1 deletes it (and falls back to INITIALS if the photo was in use). Errors 51713-51716.
CREATE PROCEDURE sec.usp_UserAvatar_Set
    @AvatarKind         VARCHAR(10),
    @PiloEmote          VARCHAR(20) = NULL,
    @PrimaryColor       CHAR(7) = NULL,
    @SecondaryColor     CHAR(7) = NULL,
    @Photo              VARBINARY(MAX) = NULL,
    @RemovePhoto        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Mime VARCHAR(20);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51713, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF @AvatarKind IS NULL OR NOT (@AvatarKind = 'INITIALS' OR @AvatarKind = 'PILO' OR @AvatarKind = 'PHOTO')
        THROW 51714, N'Avatar must be INITIALS, PILO or PHOTO.', 1;
    IF @AvatarKind = 'PILO' AND NOT EXISTS (SELECT 1 FROM admin.PiloEmote WHERE Code = @PiloEmote AND IsActive = 1)
        THROW 51714, N'Pick one of the Pilo emotes.', 1;

    IF @Photo IS NOT NULL
    BEGIN
        IF DATALENGTH(@Photo) > 262144 THROW 51715, N'The photo must be 256 KB or smaller.', 1;
        SET @Mime = CASE WHEN SUBSTRING(@Photo, 1, 8) = 0x89504E470D0A1A0A THEN 'image/png'
                         WHEN SUBSTRING(@Photo, 1, 3) = 0xFFD8FF THEN 'image/jpeg' END;
        IF @Mime IS NULL THROW 51715, N'The photo must be a PNG or JPEG image.', 1;
    END;
    IF @AvatarKind = 'PHOTO' AND @Photo IS NULL
       AND (@RemovePhoto = 1 OR NOT EXISTS (SELECT 1 FROM sec.UserAvatar WHERE TenantId = @TenantId AND AppUserId = @UserId))
        THROW 51716, N'Upload a photo first.', 1;

    BEGIN TRAN;

    IF @RemovePhoto = 1
        DELETE FROM sec.UserAvatar WHERE TenantId = @TenantId AND AppUserId = @UserId;
    ELSE IF @Photo IS NOT NULL
        MERGE sec.UserAvatar WITH (HOLDLOCK) AS t
        USING (SELECT @TenantId AS TenantId, @UserId AS AppUserId) AS s
        ON t.TenantId = s.TenantId AND t.AppUserId = s.AppUserId
        WHEN MATCHED THEN UPDATE SET ContentType = @Mime, Bytes = @Photo, UpdatedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (TenantId, AppUserId, ContentType, Bytes) VALUES (@TenantId, @UserId, @Mime, @Photo);

    UPDATE sec.AppUser
    SET AvatarKind = IIF(@RemovePhoto = 1 AND @AvatarKind = 'PHOTO', 'INITIALS', @AvatarKind),
        AvatarPiloEmote = IIF(@AvatarKind = 'PILO', @PiloEmote, AvatarPiloEmote),
        AvatarPrimaryColor = COALESCE(@PrimaryColor, AvatarPrimaryColor),
        AvatarSecondaryColor = COALESCE(@SecondaryColor, AvatarSecondaryColor),
        ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @UserId;

    COMMIT;
END;
