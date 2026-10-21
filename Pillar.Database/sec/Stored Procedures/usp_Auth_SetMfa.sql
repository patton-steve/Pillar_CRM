-- Turns TOTP on (after the user has confirmed a code against the new secret) or off (@MfaSecretEncrypted NULL) for the session user.
-- The secret is encrypted by the API; recovery codes arrive already hashed, as a JSON array.
CREATE PROCEDURE sec.usp_Auth_SetMfa
    @MfaSecretEncrypted VARBINARY(512),
    @RecoveryCodeHashes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserId INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @UserId IS NULL THROW 50953, N'No user in session.', 1;

    UPDATE sec.UserCredential
    SET MfaSecretEncrypted = @MfaSecretEncrypted,
        MfaEnabledAt = CASE WHEN @MfaSecretEncrypted IS NULL THEN NULL ELSE @Now END,
        RecoveryCodeHashes = CASE WHEN @MfaSecretEncrypted IS NULL THEN NULL ELSE @RecoveryCodeHashes END,
        ModifiedAt = @Now
    WHERE AppUserId = @UserId;

    INSERT INTO sec.LoginAudit (EventType, TenantId, AppUserId)
    SELECT CASE WHEN @MfaSecretEncrypted IS NULL THEN 'MFA_DISABLED' ELSE 'MFA_ENABLED' END, TenantId, AppUserId
    FROM sec.UserCredential WHERE AppUserId = @UserId;
END;
