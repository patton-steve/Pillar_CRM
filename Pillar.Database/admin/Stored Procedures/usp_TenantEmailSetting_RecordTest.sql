-- The API records the result of a test send through the tenant's SMTP server. Success marks the settings verified.
CREATE PROCEDURE admin.usp_TenantEmailSetting_RecordTest
    @Succeeded      BIT,
    @Error          NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId'));
    IF @TenantId IS NULL THROW 51501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    UPDATE admin.TenantEmailSetting
    SET IsVerified = @Succeeded, LastTestAt = SYSUTCDATETIME(), LastTestError = CASE WHEN @Succeeded = 1 THEN NULL ELSE @Error END
    WHERE TenantId = @TenantId;
    IF @@ROWCOUNT = 0 THROW 51504, N'Save the email settings before testing them.', 1;
END;
