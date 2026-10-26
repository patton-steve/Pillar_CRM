-- Saves toggles from the Settings > Roles permission grid for one role. Needs users.manage. The Owner role always holds
-- every permission and can't be edited. Only the codes listed change:
--   @Permissions = N'[{"code":"time.approve","on":true},{"code":"invoice.issue","on":false}]'
-- Marks the role customized (PermissionsCustomizedAt), so sec.usp_SeedTenantRoles never re-grants what was turned off.
-- Returns the role's permissions after the change. Errors 51622-51630.
CREATE PROCEDURE sec.usp_RolePermission_Set
    @RoleId         INT,
    @Permissions    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @IsOwner BIT, @Bad VARCHAR(50), @Msg NVARCHAR(400), @AuditKey NVARCHAR(100), @AuditSummary NVARCHAR(400);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51622, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage'))
        THROW 51623, N'You need permission to manage users to change roles.', 1;
    SELECT @IsOwner = IsOwner FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId;
    IF @IsOwner IS NULL THROW 51624, N'Role not found.', 1;
    IF @IsOwner = 1 THROW 51625, N'The Owner role always has every permission.', 1;
    IF ISJSON(@Permissions) <> 1 THROW 51629, N'Permissions must be a JSON array of {"code","on"}.', 1;

    DECLARE @Grid TABLE (Code VARCHAR(50) NOT NULL PRIMARY KEY, IsOn BIT NOT NULL);
    INSERT INTO @Grid (Code, IsOn)
    SELECT j.code COLLATE DATABASE_DEFAULT, MAX(CONVERT(INT, j.[on]))
    FROM OPENJSON(@Permissions) WITH (code VARCHAR(50) '$.code', [on] BIT '$.on') AS j
    WHERE j.code IS NOT NULL AND j.[on] IS NOT NULL
    GROUP BY j.code COLLATE DATABASE_DEFAULT;

    SELECT TOP (1) @Bad = g.Code FROM @Grid AS g WHERE NOT EXISTS (SELECT 1 FROM sec.Permission AS p WHERE p.Code = g.Code AND p.IsActive = 1);
    IF @Bad IS NOT NULL
    BEGIN
        SET @Msg = CONCAT(N'Unknown or retired permission: ', @Bad, N'.');
        THROW 51630, @Msg, 1;
    END;

    BEGIN TRAN;

    DELETE rp FROM sec.RolePermission AS rp
    JOIN @Grid AS g ON g.Code = rp.PermissionCode AND g.IsOn = 0
    WHERE rp.TenantId = @TenantId AND rp.RoleId = @RoleId;

    INSERT INTO sec.RolePermission (TenantId, RoleId, PermissionCode)
    SELECT @TenantId, @RoleId, g.Code FROM @Grid AS g
    WHERE g.IsOn = 1 AND NOT EXISTS (SELECT 1 FROM sec.RolePermission AS rp
                                     WHERE rp.TenantId = @TenantId AND rp.RoleId = @RoleId AND rp.PermissionCode = g.Code);

    UPDATE sec.Role SET PermissionsCustomizedAt = SYSUTCDATETIME(), ModifiedAt = SYSUTCDATETIME()
    WHERE TenantId = @TenantId AND Id = @RoleId;

    SELECT @AuditKey = Code, @AuditSummary = CONCAT(N'Changed permissions on role "', Name, N'"')
    FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId;
    EXEC admin.usp_Audit_Write @Area = 'users', @EntityType = 'ROLE_PERMISSION', @EntityKey = @AuditKey,
         @Action = 'UPDATE', @Summary = @AuditSummary, @ChangeJson = @Permissions;

    COMMIT;

    SELECT PermissionCode FROM sec.RolePermission WHERE TenantId = @TenantId AND RoleId = @RoleId ORDER BY PermissionCode;
END;
