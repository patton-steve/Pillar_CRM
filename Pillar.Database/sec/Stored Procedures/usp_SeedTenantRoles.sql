-- Gives a tenant any of Pillar's seeded roles it is missing, and adds permissions Pillar has since granted to those
-- system roles. Additive only: never removes a permission or changes a tenant-edited role.
-- Run at sign-up (admin.usp_Tenant_SignUp does). @TenantId NULL = every tenant (needs IsPlatformAdmin; the post-deploy does this).
CREATE PROCEDURE sec.usp_SeedTenantRoles
    @TenantId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO sec.Role (TenantId, Code, Name, Description, IsSystem, IsOwner, IsDefault, SortOrder)
    SELECT t.Id, d.Code, d.Name, d.Description, 1, d.IsOwner, d.IsDefault, d.SortOrder
    FROM admin.Tenant AS t
    CROSS JOIN sec.DefaultRole AS d
    WHERE (@TenantId IS NULL OR t.Id = @TenantId)
      AND NOT EXISTS (SELECT 1 FROM sec.Role AS r WHERE r.TenantId = t.Id AND r.Code = d.Code);

    INSERT INTO sec.RolePermission (TenantId, RoleId, PermissionCode)
    SELECT r.TenantId, r.Id, dp.PermissionCode
    FROM sec.Role AS r
    JOIN sec.DefaultRolePermission AS dp ON dp.RoleCode = r.Code
    WHERE r.IsSystem = 1 AND (@TenantId IS NULL OR r.TenantId = @TenantId)
      AND NOT EXISTS (SELECT 1 FROM sec.RolePermission AS x
                      WHERE x.TenantId = r.TenantId AND x.RoleId = r.Id AND x.PermissionCode = dp.PermissionCode);
END;
