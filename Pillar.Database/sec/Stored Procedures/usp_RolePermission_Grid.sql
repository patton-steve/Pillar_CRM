-- Reads the Settings > Roles permission grid for one role, built only from data: one row per active permission under
-- an active category, in category then permission order. Needs users.manage.
--   IsGranted       the role has it (the Owner role has everything)
--   IsFromBaseRole  Pillar's default for the role's archetype (BaseRoleCode) includes it: the "From Manager" chip
--   IsLocked        can't be toggled (every permission on the Owner role)
-- First result set (skip with @IncludeRole = 0): the role itself (name, archetype, flags, customized at, user count).
CREATE PROCEDURE sec.usp_RolePermission_Grid
    @RoleId         INT,
    @IncludeRole    BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @IsOwner BIT, @Base VARCHAR(20);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51622, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage'))
        THROW 51623, N'You need permission to manage users to change roles.', 1;
    SELECT @IsOwner = IsOwner, @Base = BaseRoleCode FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId;
    IF @IsOwner IS NULL THROW 51624, N'Role not found.', 1;

    IF @IncludeRole = 1
    SELECT r.Id AS RoleId, r.Code, r.Name, r.Description, r.BaseRoleCode, d.Name AS BaseRoleName, r.IsSystem, r.IsOwner,
           r.IsDefault, r.IsActive, r.PermissionsCustomizedAt,
           (SELECT COUNT(*) FROM sec.AppUser AS u WHERE u.TenantId = r.TenantId AND u.RoleId = r.Id AND u.Status <> 'DISABLED') AS UserCount
    FROM sec.Role AS r
    LEFT JOIN sec.DefaultRole AS d ON d.Code = r.BaseRoleCode
    WHERE r.TenantId = @TenantId AND r.Id = @RoleId;

    SELECT c.Code AS CategoryCode, c.Name AS CategoryName, c.Description AS CategoryDescription, c.SortOrder AS CategorySortOrder,
           p.Code AS PermissionCode, p.Name AS PermissionName, p.Description AS PermissionDescription, p.SortOrder,
           CONVERT(BIT, IIF(@IsOwner = 1 OR rp.PermissionCode IS NOT NULL, 1, 0)) AS IsGranted,
           CONVERT(BIT, IIF(@Base = 'OWNER' OR dp.PermissionCode IS NOT NULL, 1, 0)) AS IsFromBaseRole,
           @IsOwner AS IsLocked
    FROM sec.Permission AS p
    JOIN sec.PermissionCategory AS c ON c.Code = p.CategoryCode AND c.IsActive = 1
    LEFT JOIN sec.RolePermission AS rp ON rp.TenantId = @TenantId AND rp.RoleId = @RoleId AND rp.PermissionCode = p.Code
    LEFT JOIN sec.DefaultRolePermission AS dp ON dp.RoleCode = @Base AND dp.PermissionCode = p.Code
    WHERE p.IsActive = 1
    ORDER BY c.SortOrder, p.SortOrder, p.Code;
END;
