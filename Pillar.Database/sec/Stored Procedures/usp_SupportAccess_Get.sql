-- Settings > Security > Pillar support: the live grant (none = no row), then the last 20 support sign-ins (who, as whom, why,
-- when). Needs settings.security.
CREATE PROCEDURE sec.usp_SupportAccess_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.security'))
        THROW 52250, N'You don''t have permission to change support access.', 1;

    SELECT TOP (1) g.Id AS GrantId, g.GrantedAt, g.ExpiresAt, g.Note, g.GrantedBy, u.DisplayName AS GrantedByName
    FROM sec.SupportAccessGrant AS g
    JOIN sec.AppUser AS u ON u.TenantId = g.TenantId AND u.Id = g.GrantedBy
    WHERE g.TenantId = @TenantId AND g.RevokedAt IS NULL AND g.ExpiresAt > SYSUTCDATETIME()
    ORDER BY g.ExpiresAt DESC;

    SELECT TOP (20) s.Id, s.PlatformAdminName, s.AsUserId, u.DisplayName AS AsUserName, s.Reason, s.StartedAt, s.EndedAt, s.EndReason
    FROM sec.ImpersonationSession AS s
    JOIN sec.AppUser AS u ON u.TenantId = s.TenantId AND u.Id = s.AsUserId
    WHERE s.TenantId = @TenantId
    ORDER BY s.Id DESC;
END;
