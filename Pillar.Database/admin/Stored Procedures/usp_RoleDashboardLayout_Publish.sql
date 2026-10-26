-- Settings > Company > Today layouts: publishes a role's default Today layout, or removes it (@Remove = 1) so the role
-- falls back to Pillar's built-in default. Needs settings.company. People who saved their own layout keep it until they
-- pick "Reset to my role's default" (admin.usp_TodayLayout_Reset). Audited.
CREATE PROCEDURE admin.usp_RoleDashboardLayout_Publish
    @RoleId         INT,
    @LayoutJson     NVARCHAR(MAX) = NULL,
    @Remove         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @RoleName NVARCHAR(50), @Summary NVARCHAR(400), @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @RoleId);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.company'))
        THROW 52330, N'You need permission to change company settings to publish Today layouts.', 1;

    SELECT @RoleName = Name FROM sec.Role WHERE TenantId = @TenantId AND Id = @RoleId AND IsActive = 1;
    IF @RoleName IS NULL THROW 52331, N'Unknown role.', 1;

    BEGIN TRAN;

    IF @Remove = 1
    BEGIN
        DELETE FROM admin.RoleDashboardLayout WHERE TenantId = @TenantId AND RoleId = @RoleId;
        IF @@ROWCOUNT > 0
        BEGIN
            SET @Summary = CONCAT(N'Removed the Today layout for ', @RoleName);
            EXEC admin.usp_Audit_Write @Area = 'company', @EntityType = 'TODAY_LAYOUT', @EntityKey = @Key, @Action = 'DELETE', @Summary = @Summary;
        END;
    END
    ELSE
    BEGIN
        IF @LayoutJson IS NULL OR ISJSON(@LayoutJson) = 0 OR LEN(@LayoutJson) > 20000
            THROW 52332, N'The layout must be JSON of at most 20,000 characters.', 1;

        UPDATE admin.RoleDashboardLayout
        SET LayoutJson = @LayoutJson, PublishedAt = SYSUTCDATETIME(), PublishedBy = @UserId
        WHERE TenantId = @TenantId AND RoleId = @RoleId;
        IF @@ROWCOUNT = 0
            INSERT INTO admin.RoleDashboardLayout (TenantId, RoleId, LayoutJson, PublishedBy)
            VALUES (@TenantId, @RoleId, @LayoutJson, @UserId);

        SET @Summary = CONCAT(N'Published the Today layout for ', @RoleName);
        EXEC admin.usp_Audit_Write @Area = 'company', @EntityType = 'TODAY_LAYOUT', @EntityKey = @Key, @Action = 'UPDATE', @Summary = @Summary;
    END;

    COMMIT;
END;
