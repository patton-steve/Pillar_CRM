-- Back office > tenant > Users: Pillar changes someone's role or turns their access on or off (ACTIVE / DISABLED), with a reason.
-- The usual rules hold (sec.trg_AppUser_Rules: the last active owner stays, a disabled user is signed out). Logged in Pillar's
-- audit trail and in the tenant's audit log.
CREATE PROCEDURE admin.usp_PlatformUser_Update
    @TenantId   INT,
    @AppUserId  INT,
    @RoleId     INT = NULL,
    @Status     VARCHAR(10) = NULL,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;
    IF @Status IS NOT NULL AND @Status <> 'ACTIVE' AND @Status <> 'DISABLED' THROW 52256, N'Status must be ACTIVE or DISABLED.', 1;

    DECLARE @OldRole NVARCHAR(100), @NewRole NVARCHAR(100), @OldStatus VARCHAR(10), @Name NVARCHAR(200), @Change NVARCHAR(MAX),
            @Summary NVARCHAR(400), @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @AppUserId), @Now DATETIME2(0) = SYSUTCDATETIME();

    SELECT @OldRole = r.Name, @OldStatus = u.Status, @Name = u.DisplayName
    FROM sec.AppUser AS u JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId
    WHERE u.TenantId = @TenantId AND u.Id = @AppUserId;
    IF @Name IS NULL THROW 52256, N'Unknown user.', 1;
    IF @RoleId IS NOT NULL
    BEGIN
        SELECT @NewRole = Name FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId AND IsActive = 1;
        IF @NewRole IS NULL THROW 52256, N'Unknown role.', 1;
    END;

    BEGIN TRAN;
    UPDATE sec.AppUser
    SET RoleId = COALESCE(@RoleId, RoleId),
        Status = CASE WHEN @Status IS NULL OR (Status = 'INVITED' AND @Status = 'ACTIVE') THEN Status ELSE @Status END,
        DisabledAt = CASE WHEN @Status = 'DISABLED' THEN COALESCE(DisabledAt, @Now) WHEN @Status = 'ACTIVE' THEN NULL ELSE DisabledAt END,
        ModifiedAt = @Now, ModifiedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
    WHERE TenantId = @TenantId AND Id = @AppUserId;

    SET @Change = (SELECT x.field, x.[from], x.[to] FROM (VALUES
                        (N'Role', @OldRole, COALESCE(@NewRole, @OldRole)),
                        (N'Status', CONVERT(NVARCHAR(100), @OldStatus), CONVERT(NVARCHAR(100), COALESCE(@Status, @OldStatus)))) AS x (field, [from], [to])
                   WHERE x.[from] <> x.[to] FOR JSON PATH);
    SET @Summary = CONCAT(N'Pillar support updated ', @Name);
    EXEC admin.usp_PlatformAudit_Write @Action = 'UPDATE_USER', @TenantId = @TenantId, @EntityType = 'USER', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    EXEC admin.usp_Audit_Write @Area = 'users', @EntityType = 'USER', @EntityKey = @Key, @Action = 'UPDATE',
         @Summary = @Summary, @ChangeJson = @Change, @TenantId = @TenantId;
    COMMIT;
END;
