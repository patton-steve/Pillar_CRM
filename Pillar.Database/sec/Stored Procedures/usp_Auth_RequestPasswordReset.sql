-- "Forgot password" (no session context needed). Stores a RESET token for an enabled login that has a password and sets
-- @Send = 1 so the API emails the link; otherwise @Send = 0. The API shows the same message either way (no account probing).
CREATE PROCEDURE sec.usp_Auth_RequestPasswordReset
    @Email          NVARCHAR(254),
    @TokenHash      BINARY(32),
    @ExpiresAt      DATETIME2(0) = NULL,    -- default 1 hour
    @Send           BIT = 0 OUTPUT,
    @IpAddress      VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @AppUserId INT, @TenantId INT;
    SET @Send = 0;

    SELECT @AppUserId = AppUserId, @TenantId = TenantId
    FROM sec.UserCredential
    WHERE LoginEmail = LOWER(LTRIM(RTRIM(@Email))) AND IsEnabled = 1 AND PasswordHash IS NOT NULL;

    IF @AppUserId IS NULL RETURN;

    BEGIN TRAN;
    UPDATE sec.UserToken SET RevokedAt = @Now
    WHERE AppUserId = @AppUserId AND Purpose = 'RESET' AND UsedAt IS NULL AND RevokedAt IS NULL;
    INSERT INTO sec.UserToken (TenantId, AppUserId, Purpose, TokenHash, ExpiresAt)
    VALUES (@TenantId, @AppUserId, 'RESET', @TokenHash, COALESCE(@ExpiresAt, DATEADD(HOUR, 1, @Now)));
    INSERT INTO sec.LoginAudit (EventType, Email, TenantId, AppUserId, IpAddress)
    VALUES ('RESET_REQUESTED', LOWER(LTRIM(RTRIM(@Email))), @TenantId, @AppUserId, @IpAddress);
    COMMIT;

    SET @Send = 1;
END;
