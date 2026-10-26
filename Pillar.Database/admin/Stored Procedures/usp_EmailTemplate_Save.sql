-- Adds or edits an email template (Settings > Email templates; needs settings.email). @IsDefault = 1 makes it the tenant's
-- default for its type (the previous default stops being one). @Delete = 1 removes it: the default can't be deleted,
-- and billing profiles that used it fall back to the default. TemplateType never changes once saved.
CREATE PROCEDURE admin.usp_EmailTemplate_Save
    @TemplateId     INT = NULL OUTPUT,
    @TemplateType   VARCHAR(20) = 'INVOICE',
    @Name           NVARCHAR(100) = NULL,
    @Subject        NVARCHAR(300) = NULL,
    @BodyHtml       NVARCHAR(MAX) = NULL,
    @IsDefault      BIT = 0,
    @Delete         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(), @OldType VARCHAR(20), @WasDefault BIT,
            @AuditKey NVARCHAR(100), @AuditSummary NVARCHAR(400), @AuditAction VARCHAR(10) = IIF(@TemplateId IS NULL, 'CREATE', 'UPDATE');
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.email'))
        THROW 51505, N'You need permission to change settings to manage email templates.', 1;

    IF @TemplateId IS NOT NULL
    BEGIN
        SELECT @OldType = TemplateType, @WasDefault = IsDefault FROM admin.EmailTemplate
        WHERE TenantId = @TenantId AND Id = @TemplateId AND DeletedAt IS NULL;
        IF @OldType IS NULL THROW 51506, N'Email template not found.', 1;
        SET @TemplateType = @OldType;
    END;

    BEGIN TRAN;

    IF @Delete = 1
    BEGIN
        IF @WasDefault = 1 THROW 51507, N'Make another template the default before deleting this one.', 1;
        UPDATE crm.ClientBillingProfile SET InvoiceEmailTemplateId = NULL
        WHERE TenantId = @TenantId AND InvoiceEmailTemplateId = @TemplateId;
        UPDATE admin.EmailTemplate SET DeletedAt = @Now, ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @TemplateId;
        SET @AuditKey = CONVERT(NVARCHAR(100), @TemplateId);
        EXEC admin.usp_Audit_Write @Area = 'email', @EntityType = 'EMAIL_TEMPLATE', @EntityKey = @AuditKey,
             @Action = 'DELETE', @Summary = N'Deleted an email template';
        COMMIT;
        RETURN;
    END;

    IF NULLIF(LTRIM(@Name), N'') IS NULL OR NULLIF(LTRIM(@Subject), N'') IS NULL OR NULLIF(LTRIM(@BodyHtml), N'') IS NULL
        THROW 51508, N'An email template needs a name, a subject and a body.', 1;
    -- the first template of a type becomes its default
    IF NOT EXISTS (SELECT 1 FROM admin.EmailTemplate WHERE TenantId = @TenantId AND TemplateType = @TemplateType AND IsDefault = 1)
        SET @IsDefault = 1;
    IF @IsDefault = 1
        UPDATE admin.EmailTemplate SET IsDefault = 0, ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND TemplateType = @TemplateType AND IsDefault = 1 AND Id <> ISNULL(@TemplateId, 0);

    IF @TemplateId IS NULL
    BEGIN
        INSERT INTO admin.EmailTemplate (TenantId, TemplateType, Name, Subject, BodyHtml, IsDefault)
        VALUES (@TenantId, @TemplateType, @Name, @Subject, @BodyHtml, @IsDefault);
        SET @TemplateId = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE admin.EmailTemplate
        SET Name = @Name, Subject = @Subject, BodyHtml = @BodyHtml, IsDefault = IIF(@IsDefault = 1, 1, IsDefault),
            ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @TemplateId;

    SELECT @AuditKey = CONVERT(NVARCHAR(100), @TemplateId), @AuditSummary = CONCAT(N'Saved ', @TemplateType, N' email template "', @Name, N'"');
    EXEC admin.usp_Audit_Write @Area = 'email', @EntityType = 'EMAIL_TEMPLATE', @EntityKey = @AuditKey,
         @Action = @AuditAction, @Summary = @AuditSummary;

    COMMIT;
END;
