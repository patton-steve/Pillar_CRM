-- Sign-in step 1 (no session context needed): the stored login for an email, for the API to check the password with bcrypt.
-- No row = no such login; the API answers "invalid email or password" either way and records the attempt
-- with sec.usp_Auth_RecordLogin. A locked or disabled login must be refused even when the password matches.
-- Handoff 22: TenantStatus decides where the API sends the person (admin.Tenant has the list): SETUP goes to email verification
-- (EmailVerified = 0) or the setup wizard, PENDING_REVIEW and DECLINED to the "under review" / "not approved" screen,
-- SUSPENDED and CANCELLED are refused. Sign-in step 2 (sec.usp_Auth_SecurityPolicy) adds MFA and terms checks.
CREATE PROCEDURE sec.usp_Auth_GetLogin
    @Email NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT c.AppUserId, c.TenantId, c.PasswordHash, c.IsEnabled,
           CAST(CASE WHEN c.LockedUntil > SYSUTCDATETIME() THEN 1 ELSE 0 END AS BIT) AS IsLocked,
           c.LockedUntil,
           CAST(CASE WHEN c.MfaEnabledAt IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS MfaEnabled,
           c.MfaSecretEncrypted, c.RecoveryCodeHashes, c.MustChangePassword,
           t.Status AS TenantStatus,
           CAST(CASE WHEN c.EmailVerifiedAt IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS EmailVerified
    FROM sec.UserCredential AS c
    JOIN admin.Tenant AS t ON t.Id = c.TenantId
    WHERE c.LoginEmail = LOWER(LTRIM(RTRIM(@Email)));
END;
