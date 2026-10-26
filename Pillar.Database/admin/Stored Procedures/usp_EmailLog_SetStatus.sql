-- The API records the outcome of a queued email: SENT (stamps SentAt) or FAILED with the server's error.
CREATE PROCEDURE admin.usp_EmailLog_SetStatus
    @EmailLogId     BIGINT,
    @Succeeded      BIT,
    @Error          NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId'));
    IF @TenantId IS NULL THROW 51501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    UPDATE admin.EmailLog
    SET Status = IIF(@Succeeded = 1, 'SENT', 'FAILED'),
        SentAt = IIF(@Succeeded = 1, SYSUTCDATETIME(), NULL),
        Error  = IIF(@Succeeded = 1, NULL, @Error)
    WHERE TenantId = @TenantId AND Id = @EmailLogId;
    IF @@ROWCOUNT = 0 THROW 51513, N'Email log entry not found.', 1;
END;
