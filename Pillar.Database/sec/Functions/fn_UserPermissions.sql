-- Every permission the user holds: what the API puts in the session (or JWT) at sign-in and the UI uses to show/hide actions.
CREATE FUNCTION sec.fn_UserPermissions (@TenantId INT, @AppUserId INT)
RETURNS TABLE
AS
RETURN
    SELECT p.Code AS PermissionCode
    FROM sec.AppUser AS u
    JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsActive = 1
    JOIN sec.Permission AS p
      ON p.IsActive = 1 AND (r.IsOwner = 1
      OR EXISTS (SELECT 1 FROM sec.RolePermission AS rp
                 WHERE rp.TenantId = r.TenantId AND rp.RoleId = r.Id AND rp.PermissionCode = p.Code))
    WHERE u.TenantId = @TenantId AND u.Id = @AppUserId AND u.Status = 'ACTIVE';
