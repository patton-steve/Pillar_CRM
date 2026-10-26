-- Settings > Company > Today layouts: every active role with its archetype, user count and published layout (NULL = the
-- role uses Pillar's built-in default for BaseRoleCode). Needs settings.company.
CREATE PROCEDURE admin.usp_RoleDashboardLayout_List
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.company'))
        THROW 52330, N'You need permission to change company settings to publish Today layouts.', 1;

    SELECT r.Id AS RoleId, r.Name AS RoleName, r.IsOwner, ISNULL(r.BaseRoleCode, IIF(r.IsOwner = 1, 'OWNER', NULL)) AS BaseRoleCode,
           (SELECT COUNT(*) FROM sec.AppUser AS u WHERE u.TenantId = r.TenantId AND u.RoleId = r.Id AND u.Status <> 'DISABLED') AS UserCount,
           CONVERT(BIT, IIF(l.RoleId IS NULL, 0, 1)) AS HasLayout, l.LayoutJson, l.PublishedAt, l.PublishedBy,
           p.DisplayName AS PublishedByName
    FROM sec.Role AS r
    LEFT JOIN admin.RoleDashboardLayout AS l ON l.TenantId = r.TenantId AND l.RoleId = r.Id
    LEFT JOIN sec.AppUser AS p ON p.TenantId = l.TenantId AND p.Id = l.PublishedBy
    WHERE r.TenantId = @TenantId AND r.IsActive = 1
    ORDER BY r.SortOrder, r.Name;
END;
