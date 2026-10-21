-- Saves (or with @LogoImage = NULL, removes) the session tenant's invoice logo.
-- The type comes from the file's own signature, not the upload's name or header: PNG or JPEG only, 512 KB max.
-- Creates the admin.TenantBranding row on first use.
CREATE PROCEDURE admin.usp_TenantBranding_SetLogo
    @LogoImage      VARBINARY(MAX),
    @LogoFileName   NVARCHAR(260) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @MimeType VARCHAR(20);

    IF @TenantId IS NULL THROW 50911, N'No tenant in session.', 1;

    IF @LogoImage IS NOT NULL
    BEGIN
        IF DATALENGTH(@LogoImage) > 524288 THROW 50912, N'The logo must be 512 KB or smaller.', 1;

        SET @MimeType = CASE
            WHEN SUBSTRING(@LogoImage, 1, 8) = 0x89504E470D0A1A0A THEN 'image/png'
            WHEN SUBSTRING(@LogoImage, 1, 3) = 0xFFD8FF THEN 'image/jpeg'
        END;
        IF @MimeType IS NULL THROW 50913, N'The logo must be a PNG or JPEG image.', 1;
    END;

    MERGE admin.TenantBranding WITH (HOLDLOCK) AS t
    USING (SELECT @TenantId AS TenantId) AS s
    ON t.TenantId = s.TenantId
    WHEN MATCHED THEN UPDATE SET
        LogoImage = @LogoImage, LogoMimeType = @MimeType,
        LogoFileName = CASE WHEN @LogoImage IS NULL THEN NULL ELSE @LogoFileName END,
        LogoUpdatedAt = @Now, LogoUpdatedBy = @UserId, ModifiedAt = @Now, ModifiedBy = @UserId
    WHEN NOT MATCHED AND @LogoImage IS NOT NULL THEN
        INSERT (TenantId, LogoImage, LogoMimeType, LogoFileName, LogoUpdatedAt, LogoUpdatedBy)
        VALUES (@TenantId, @LogoImage, @MimeType, @LogoFileName, @Now, @UserId);
END;
