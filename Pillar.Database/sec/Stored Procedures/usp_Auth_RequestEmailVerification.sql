-- Stores a new VERIFY link for a login whose email isn't verified yet ("Resend the email" on the verify screen; no session needed).
-- Earlier unused VERIFY links are revoked. The API emails the raw token and passes only its SHA-256 hash.
CREATE PROCEDURE sec.usp_Auth_RequestEmailVerification
    @AppUserId      INT,
    @TokenHash      BINARY(32),
    @ExpiresAt      DATETIME2(0) = NULL     -- default 24 hours
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @TenantId INT, @Verified DATETIME2(0);

    SELECT @TenantId = TenantId, @Verified = EmailVerifiedAt FROM sec.UserCredential WHERE AppUserId = @AppUserId AND IsEnabled = 1;
    IF @TenantId IS NULL THROW 52215, N'Unknown login.', 1;
    IF @Verified IS NOT NULL THROW 52214, N'This email is already verified.', 1;

    BEGIN TRAN;
    UPDATE sec.UserToken SET RevokedAt = @Now
    WHERE AppUserId = @AppUserId AND Purpose = 'VERIFY' AND UsedAt IS NULL AND RevokedAt IS NULL;
    INSERT INTO sec.UserToken (TenantId, AppUserId, Purpose, TokenHash, ExpiresAt)
    VALUES (@TenantId, @AppUserId, 'VERIFY', @TokenHash, COALESCE(@ExpiresAt, DATEADD(HOUR, 24, @Now)));
    COMMIT;
END;
