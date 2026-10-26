-- Sign-in step 2, after the password checks out: the API sets SESSION_CONTEXT TenantId (from usp_Auth_GetLogin) and reads
-- the tenant's security rules here. MustEnrollMfa = 1 means Security.RequireMfa is on, or the person is Pillar staff
-- (IsPlatformAdmin: MFA is always required for the back office, handoff 22), and they have no authenticator yet: the API sends
-- them to MFA setup before issuing tokens. The password rules apply when a password is set or changed;
-- SessionTimeoutMinutes (0 = never) and MaxSessionDays size the refresh token.
-- Handoff 22: TenantStatus and EmailVerified repeat step 1's answer; MustAcceptTermsId is the current terms of service when it
-- needs (re)accepting (sec.usp_Legal_Accept), NULL otherwise. The API sets the IsPlatformAdmin session flag only on back-office
-- routes, and only for IsPlatformAdmin = 1 people who signed in with MFA.
CREATE PROCEDURE sec.usp_Auth_SecurityPolicy
    @AppUserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId'));
    IF @TenantId IS NULL THROW 51722, N'Set SESSION_CONTEXT TenantId to the login''s tenant first.', 1;

    SELECT CONVERT(BIT, ISNULL(TRY_CONVERT(INT, mfa.Value), 0)) AS RequireMfa,
           CONVERT(BIT, IIF((ISNULL(TRY_CONVERT(INT, mfa.Value), 0) = 1 OR u.IsPlatformAdmin = 1) AND c.MfaEnabledAt IS NULL, 1, 0)) AS MustEnrollMfa,
           TRY_CONVERT(INT, len.Value) AS PasswordMinLength,
           CONVERT(BIT, ISNULL(TRY_CONVERT(INT, mix.Value), 0)) AS PasswordRequireMixed,
           TRY_CONVERT(INT, idle.Value) AS SessionTimeoutMinutes,
           TRY_CONVERT(INT, life.Value) AS MaxSessionDays,
           u.IsPlatformAdmin,
           t.Status AS TenantStatus,
           CONVERT(BIT, IIF(c.EmailVerifiedAt IS NOT NULL, 1, 0)) AS EmailVerified,
           tos.Id AS MustAcceptTermsId
    FROM sec.UserCredential AS c
    JOIN sec.AppUser AS u ON u.TenantId = c.TenantId AND u.Id = c.AppUserId
    JOIN admin.Tenant AS t ON t.Id = c.TenantId
    OUTER APPLY admin.fn_Setting(@TenantId, NULL, 'Security.RequireMfa') AS mfa
    OUTER APPLY admin.fn_Setting(@TenantId, NULL, 'Security.PasswordMinLength') AS len
    OUTER APPLY admin.fn_Setting(@TenantId, NULL, 'Security.PasswordRequireMixed') AS mix
    OUTER APPLY admin.fn_Setting(@TenantId, NULL, 'Security.SessionTimeoutMinutes') AS idle
    OUTER APPLY admin.fn_Setting(@TenantId, NULL, 'Security.MaxSessionDays') AS life
    OUTER APPLY (
        -- the current TOS, unless the person accepted it or any version since the last one that required acceptance
        SELECT cur.Id
        FROM (SELECT TOP (1) d.Id FROM admin.LegalDocument AS d
              WHERE d.Code = 'TOS' AND d.PublishedAt <= SYSUTCDATETIME() ORDER BY d.PublishedAt DESC, d.Id DESC) AS cur
        WHERE NOT EXISTS (
            SELECT 1 FROM sec.UserLegalAcceptance AS a
            JOIN admin.LegalDocument AS ad ON ad.Id = a.DocumentId AND ad.Code = 'TOS'
            WHERE a.TenantId = c.TenantId AND a.AppUserId = c.AppUserId
              AND ad.PublishedAt >= ISNULL((SELECT MAX(r.PublishedAt) FROM admin.LegalDocument AS r
                                            WHERE r.Code = 'TOS' AND r.RequiresAcceptance = 1 AND r.PublishedAt <= SYSUTCDATETIME()),
                                           CONVERT(DATETIME2(0), '19000101')))
    ) AS tos
    WHERE c.AppUserId = @AppUserId AND c.TenantId = @TenantId;
END;
