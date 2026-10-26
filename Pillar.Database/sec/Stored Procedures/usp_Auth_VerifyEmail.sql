-- Redeems a VERIFY link (no sign-in needed): marks the login's email verified and the link used, and logs EMAIL_VERIFIED.
-- Returns one row (AppUserId, TenantId) on success; no row = invalid or expired link.
CREATE PROCEDURE sec.usp_Auth_VerifyEmail
    @TokenHash      BINARY(32),
    @IpAddress      VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @TokenId INT, @AppUserId INT, @TenantId INT;

    BEGIN TRAN;

    SELECT @TokenId = t.Id, @AppUserId = t.AppUserId, @TenantId = t.TenantId
    FROM sec.UserToken AS t WITH (UPDLOCK)
    JOIN sec.UserCredential AS c ON c.AppUserId = t.AppUserId AND c.IsEnabled = 1
    WHERE t.TokenHash = @TokenHash AND t.Purpose = 'VERIFY'
      AND t.UsedAt IS NULL AND t.RevokedAt IS NULL AND t.ExpiresAt > @Now;

    IF @TokenId IS NULL
    BEGIN
        COMMIT;
        RETURN;
    END;

    UPDATE sec.UserToken SET UsedAt = @Now WHERE Id = @TokenId;
    UPDATE sec.UserCredential SET EmailVerifiedAt = COALESCE(EmailVerifiedAt, @Now), ModifiedAt = @Now WHERE AppUserId = @AppUserId;
    INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId, IpAddress) VALUES ('EMAIL_VERIFIED', @TenantId, @AppUserId, @IpAddress);

    COMMIT;

    SELECT @AppUserId AS AppUserId, @TenantId AS TenantId;
END;
