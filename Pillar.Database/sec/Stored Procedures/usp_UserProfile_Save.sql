-- My profile: the signed-in person saves their own name, title, phone, time zone and email signature. Pass only what
-- changes; @Clear* empties an optional field. Email is not here: only an admin changes it (sec.usp_User_ChangeEmail).
-- @EmailSignatureHtml must already be sanitized by the API. Errors 51711-51712.
CREATE PROCEDURE sec.usp_UserProfile_Save
    @FirstName          NVARCHAR(100) = NULL,
    @LastName           NVARCHAR(100) = NULL,
    @Title              NVARCHAR(100) = NULL,
    @Phone              NVARCHAR(30) = NULL,
    @TimeZoneId         NVARCHAR(64) = NULL,
    @EmailSignatureHtml NVARCHAR(MAX) = NULL,
    @ClearLastName      BIT = 0,
    @ClearTitle         BIT = 0,
    @ClearPhone         BIT = 0,
    @ClearTimeZone      BIT = 0,
    @ClearSignature     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51711, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF @FirstName IS NOT NULL AND NULLIF(LTRIM(@FirstName), N'') IS NULL THROW 51712, N'First name can''t be empty.', 1;
    IF @TimeZoneId IS NOT NULL
    BEGIN
        DECLARE @Probe DATETIMEOFFSET(0);
        BEGIN TRY
            SET @Probe = SYSUTCDATETIME() AT TIME ZONE @TimeZoneId;   -- unknown names raise an error
        END TRY
        BEGIN CATCH
            THROW 51712, N'Unknown time zone.', 1;
        END CATCH;
    END;

    UPDATE sec.AppUser
    SET FirstName = COALESCE(LTRIM(RTRIM(@FirstName)), FirstName),
        LastName = CASE WHEN @ClearLastName = 1 THEN NULL ELSE COALESCE(@LastName, LastName) END,
        Title = CASE WHEN @ClearTitle = 1 THEN NULL ELSE COALESCE(@Title, Title) END,
        Phone = CASE WHEN @ClearPhone = 1 THEN NULL ELSE COALESCE(@Phone, Phone) END,
        TimeZoneId = CASE WHEN @ClearTimeZone = 1 THEN NULL ELSE COALESCE(@TimeZoneId, TimeZoneId) END,
        EmailSignatureHtml = CASE WHEN @ClearSignature = 1 THEN NULL ELSE COALESCE(@EmailSignatureHtml, EmailSignatureHtml) END,
        ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    WHERE TenantId = @TenantId AND Id = @UserId;
END;
