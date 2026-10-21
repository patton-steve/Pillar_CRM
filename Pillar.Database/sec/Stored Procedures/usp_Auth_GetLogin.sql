-- Sign-in step 1 (no session context needed): the stored login for an email, for the API to check the password with bcrypt.
-- No row = no such login; the API answers "invalid email or password" either way and records the attempt
-- with sec.usp_Auth_RecordLogin. A locked or disabled login must be refused even when the password matches.
CREATE PROCEDURE sec.usp_Auth_GetLogin
    @Email NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT c.AppUserId, c.TenantId, c.PasswordHash, c.IsEnabled,
           CAST(CASE WHEN c.LockedUntil > SYSUTCDATETIME() THEN 1 ELSE 0 END AS BIT) AS IsLocked,
           c.LockedUntil,
           CAST(CASE WHEN c.MfaEnabledAt IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS MfaEnabled,
           c.MfaSecretEncrypted, c.RecoveryCodeHashes, c.MustChangePassword
    FROM sec.UserCredential AS c
    WHERE c.LoginEmail = LOWER(LTRIM(RTRIM(@Email)));
END;
