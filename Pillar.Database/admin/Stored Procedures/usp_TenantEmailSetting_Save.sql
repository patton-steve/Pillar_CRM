-- Saves the tenant's SMTP settings (Settings > Email; needs settings.email). @PasswordSecretRef is the name of the secret
-- the API stored the password under, never the password itself; NULL keeps the current one. Changing the server, port,
-- TLS, account, secret or from address clears IsVerified, so the API must send a test (usp_TenantEmailSetting_RecordTest).
CREATE PROCEDURE admin.usp_TenantEmailSetting_Save
    @Host               NVARCHAR(255),
    @Port               INT,
    @UseTls             BIT = 1,
    @Username           NVARCHAR(255) = NULL,
    @PasswordSecretRef  NVARCHAR(200) = NULL,
    @FromAddress        NVARCHAR(254),
    @FromName           NVARCHAR(100) = NULL,
    @ReplyTo            NVARCHAR(254) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.email'))
        THROW 51502, N'You need permission to change settings to set up email.', 1;
    IF NULLIF(LTRIM(@Host), N'') IS NULL OR @FromAddress NOT LIKE '%_@_%._%'
        THROW 51503, N'Enter the mail server and a valid from address.', 1;

    MERGE admin.TenantEmailSetting AS t
    USING (SELECT @TenantId AS TenantId) AS s ON t.TenantId = s.TenantId
    WHEN MATCHED THEN UPDATE SET
        IsVerified = CASE WHEN t.Host <> @Host OR t.Port <> @Port OR t.UseTls <> @UseTls
                               OR ISNULL(t.Username, N'') <> ISNULL(@Username, N'')
                               OR (@PasswordSecretRef IS NOT NULL AND ISNULL(t.PasswordSecretRef, N'') <> @PasswordSecretRef)
                               OR t.FromAddress <> @FromAddress
                          THEN 0 ELSE t.IsVerified END,
        Host = @Host, Port = @Port, UseTls = @UseTls, Username = @Username,
        PasswordSecretRef = COALESCE(@PasswordSecretRef, t.PasswordSecretRef),
        FromAddress = @FromAddress, FromName = @FromName, ReplyTo = @ReplyTo,
        ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    WHEN NOT MATCHED THEN INSERT (TenantId, Host, Port, UseTls, Username, PasswordSecretRef, FromAddress, FromName, ReplyTo, ModifiedBy)
        VALUES (@TenantId, @Host, @Port, @UseTls, @Username, @PasswordSecretRef, @FromAddress, @FromName, @ReplyTo, @UserId);

    DECLARE @AuditSummary NVARCHAR(400) = CONCAT(N'Saved mail server ', @Host, N':', @Port, N' sending as ', @FromAddress);
    EXEC admin.usp_Audit_Write @Area = 'email', @EntityType = 'EMAIL_SETTING', @Action = 'UPDATE', @Summary = @AuditSummary;
END;
