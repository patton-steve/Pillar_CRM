-- One row (Allowed = 1) when the user is ACTIVE and its role grants @PermissionCode; owners hold every permission.
-- Usage: IF EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.approve')) ...
CREATE FUNCTION sec.fn_UserHasPermission (@TenantId INT, @AppUserId INT, @PermissionCode VARCHAR(50))
RETURNS TABLE
AS
RETURN
    SELECT CAST(1 AS BIT) AS Allowed
    FROM sec.AppUser AS u
    JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsActive = 1
    WHERE u.TenantId = @TenantId AND u.Id = @AppUserId AND u.Status = 'ACTIVE'
      AND (r.IsOwner = 1
           OR EXISTS (SELECT 1 FROM sec.RolePermission AS rp
                      WHERE rp.TenantId = r.TenantId AND rp.RoleId = r.Id AND rp.PermissionCode = @PermissionCode));
