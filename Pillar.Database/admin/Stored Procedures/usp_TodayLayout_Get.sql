-- The session user's Today layout. Source says where it came from:
--   USER     their own layout (admin.UserPreference 'ui.todayLayout', saved with admin.usp_UserPreference_Set)
--   ROLE     the layout an admin published for their role
--   DEFAULT  neither: LayoutJson is NULL and the API uses Pillar's built-in default for BaseRoleCode
-- RoleLayoutJson is also returned so "Reset to my role's default" can preview it.
CREATE PROCEDURE admin.usp_TodayLayout_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT COALESCE(p.Value, l.LayoutJson) AS LayoutJson,
           CASE WHEN p.Value IS NOT NULL THEN 'USER' WHEN l.LayoutJson IS NOT NULL THEN 'ROLE' ELSE 'DEFAULT' END AS Source,
           r.Id AS RoleId, r.Name AS RoleName, ISNULL(r.BaseRoleCode, IIF(r.IsOwner = 1, 'OWNER', 'MEMBER')) AS BaseRoleCode,
           l.LayoutJson AS RoleLayoutJson, l.PublishedAt AS RoleLayoutPublishedAt
    FROM sec.AppUser AS u
    JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId
    LEFT JOIN admin.RoleDashboardLayout AS l ON l.TenantId = r.TenantId AND l.RoleId = r.Id
    LEFT JOIN admin.UserPreference AS p ON p.TenantId = u.TenantId AND p.AppUserId = u.Id AND p.PrefKey = 'ui.todayLayout'
    WHERE u.TenantId = @TenantId AND u.Id = @UserId;
END;
