-- Settings > Roles: add a role, rename it, make it the default for invites, or retire it. Needs users.manage.
--   New role: @Name, optionally @CopyFromRoleId to start from that role's permissions and archetype (copying Owner
--   grants every permission explicitly, archetype ADMIN; only the seeded Owner role is ever an owner).
--   Without a copy it starts with no permissions, archetype MEMBER. Set permissions with sec.usp_RolePermission_Set.
--   Existing role: pass only what changes. The Owner role can't be changed. A role can be retired (@IsActive = 0)
--   only when nobody has it and it isn't the default for invites.
-- Errors 51622-51628.
CREATE PROCEDURE sec.usp_Role_Save
    @RoleId         INT = NULL OUTPUT,
    @Name           NVARCHAR(50) = NULL,
    @Description    NVARCHAR(400) = NULL,
    @CopyFromRoleId INT = NULL,
    @IsDefault      BIT = NULL,
    @IsActive       BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @IsOwner BIT, @WasDefault BIT, @WasActive BIT, @Base VARCHAR(20), @CopyOwner BIT, @Code VARCHAR(20), @Next INT,
            @AuditKey NVARCHAR(100), @AuditSummary NVARCHAR(400), @AuditAction VARCHAR(10) = IIF(@RoleId IS NULL, 'CREATE', 'UPDATE');

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51622, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'users.manage'))
        THROW 51623, N'You need permission to manage users to change roles.', 1;

    BEGIN TRAN;

    IF @RoleId IS NOT NULL
    BEGIN
        SELECT @IsOwner = IsOwner, @WasDefault = IsDefault, @WasActive = IsActive
        FROM sec.Role WITH (UPDLOCK) WHERE TenantId = @TenantId AND Id = @RoleId;
        IF @IsOwner IS NULL THROW 51624, N'Role not found.', 1;
        IF @IsOwner = 1 THROW 51625, N'The Owner role can''t be changed.', 1;
    END;

    SET @Name = NULLIF(LTRIM(RTRIM(@Name)), N'');
    IF @RoleId IS NULL AND @Name IS NULL THROW 51626, N'A role needs a name.', 1;
    IF @Name IS NOT NULL AND EXISTS (SELECT 1 FROM sec.Role
                                     WHERE TenantId = @TenantId AND Name = @Name AND IsActive = 1 AND Id <> ISNULL(@RoleId, 0))
        THROW 51626, N'Another role already has that name.', 1;

    IF @IsActive = 0 AND ISNULL(@WasActive, 1) = 1 AND @RoleId IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM sec.AppUser WHERE TenantId = @TenantId AND RoleId = @RoleId)
            THROW 51627, N'Move everyone off this role before retiring it.', 1;
        IF @WasDefault = 1 OR @IsDefault = 1 THROW 51627, N'Make another role the default for invites before retiring this one.', 1;
    END;

    IF @RoleId IS NULL
    BEGIN
        IF @CopyFromRoleId IS NOT NULL
        BEGIN
            SELECT @Base = ISNULL(BaseRoleCode, 'MEMBER'), @CopyOwner = IsOwner
            FROM sec.Role WHERE TenantId = @TenantId AND Id = @CopyFromRoleId;
            IF @Base IS NULL THROW 51628, N'The role to copy was not found.', 1;
            IF @CopyOwner = 1 SET @Base = 'ADMIN';
        END;

        SELECT @Next = ISNULL(MAX(TRY_CONVERT(INT, SUBSTRING(Code, 8, 12))), 0) + 1
        FROM sec.Role WITH (UPDLOCK, HOLDLOCK)
        WHERE TenantId = @TenantId AND Code LIKE 'CUSTOM[_]%';
        SET @Code = CONCAT('CUSTOM_', @Next);

        INSERT INTO sec.Role (TenantId, Code, Name, Description, IsSystem, IsOwner, IsDefault, IsActive, SortOrder, BaseRoleCode)
        VALUES (@TenantId, @Code, @Name, @Description, 0, 0, 0, 1,
                (SELECT ISNULL(MAX(SortOrder), 0) + 10 FROM sec.Role WHERE TenantId = @TenantId), ISNULL(@Base, 'MEMBER'));
        SET @RoleId = SCOPE_IDENTITY();

        IF @CopyOwner = 1
            INSERT INTO sec.RolePermission (TenantId, RoleId, PermissionCode)
            SELECT @TenantId, @RoleId, Code FROM sec.Permission WHERE IsActive = 1;
        ELSE IF @CopyFromRoleId IS NOT NULL
            INSERT INTO sec.RolePermission (TenantId, RoleId, PermissionCode)
            SELECT @TenantId, @RoleId, PermissionCode FROM sec.RolePermission WHERE TenantId = @TenantId AND RoleId = @CopyFromRoleId;
    END
    ELSE
        UPDATE sec.Role
        SET Name = ISNULL(@Name, Name), Description = ISNULL(@Description, Description),
            IsActive = ISNULL(@IsActive, IsActive), ModifiedAt = @Now
        WHERE TenantId = @TenantId AND Id = @RoleId;

    IF @IsDefault = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId AND IsActive = 0)
            THROW 51627, N'A retired role can''t be the default for invites.', 1;
        UPDATE sec.Role SET IsDefault = IIF(Id = @RoleId, 1, 0), ModifiedAt = @Now
        WHERE TenantId = @TenantId AND (Id = @RoleId OR IsDefault = 1);
    END;

    SELECT @AuditKey = Code, @AuditSummary = CONCAT(IIF(@AuditAction = 'CREATE', N'Added role "', N'Changed role "'), Name, N'"',
           IIF(IsActive = 0, N' (retired)', N''))
    FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId;
    EXEC admin.usp_Audit_Write @Area = 'users', @EntityType = 'ROLE', @EntityKey = @AuditKey,
         @Action = @AuditAction, @Summary = @AuditSummary;

    COMMIT;
END;
