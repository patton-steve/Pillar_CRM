-- Records an email the API is about to send (e.g. the invoice run wizard's bulk send). Invoices must be issued;
-- needs invoice.issue. The API then sends through the tenant's SMTP and calls admin.usp_EmailLog_SetStatus.
CREATE PROCEDURE admin.usp_EmailLog_Queue
    @EntityType     VARCHAR(20),
    @EntityId       INT,
    @ToAddresses    NVARCHAR(1000),
    @Subject        NVARCHAR(300),
    @TemplateId     INT = NULL,
    @CcAddresses    NVARCHAR(1000) = NULL,
    @EmailLogId     BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'invoice.issue'))
        THROW 51509, N'You don''t have permission to email invoices.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.TenantEmailSetting WHERE TenantId = @TenantId AND IsVerified = 1)
        THROW 51510, N'Set up and test your email settings first.', 1;
    IF NULLIF(LTRIM(@ToAddresses), N'') IS NULL THROW 51511, N'Add at least one recipient.', 1;
    IF @EntityType = 'INVOICE' AND NOT EXISTS (SELECT 1 FROM ar.Invoice WHERE TenantId = @TenantId AND Id = @EntityId AND IssuedAt IS NOT NULL)
        THROW 51512, N'Only issued invoices can be emailed.', 1;
    IF @EntityType = 'CREDIT_MEMO' AND NOT EXISTS (SELECT 1 FROM ar.CreditMemo WHERE TenantId = @TenantId AND Id = @EntityId)
        THROW 51512, N'Credit memo not found.', 1;

    INSERT INTO admin.EmailLog (TenantId, EntityType, EntityId, TemplateId, ToAddresses, CcAddresses, Subject)
    VALUES (@TenantId, @EntityType, @EntityId, @TemplateId, @ToAddresses, @CcAddresses, @Subject);
    SET @EmailLogId = SCOPE_IDENTITY();
END;
