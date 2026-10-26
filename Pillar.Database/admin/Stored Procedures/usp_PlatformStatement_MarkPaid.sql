-- Back office > Failed charges > Mark paid: Pillar records the balance as paid outside the card processor (a check, a wire, or a
-- write-off), with a required reason kept on the payment row and in Pillar's audit trail.
CREATE PROCEDURE admin.usp_PlatformStatement_MarkPaid
    @StatementId    INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @TenantId INT, @Balance DECIMAL(19,2), @Number VARCHAR(20), @Summary NVARCHAR(400), @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @StatementId);
    SELECT @TenantId = TenantId, @Balance = BalanceDue, @Number = StatementNumber
    FROM admin.PlatformStatement WHERE Id = @StatementId AND (Status = 'OPEN' OR Status = 'PAST_DUE');
    IF @TenantId IS NULL OR @Balance <= 0 THROW 52240, N'Only an open or past-due statement with a balance can be marked paid.', 1;

    BEGIN TRAN;
    EXEC admin.usp_PlatformStatement_RecordPayment @StatementId = @StatementId, @Amount = @Balance, @Succeeded = 1, @Note = @Reason;
    SET @Summary = CONCAT(N'Marked ', @Number, N' paid (', FORMAT(@Balance, 'C', 'en-US'), N')');
    EXEC admin.usp_PlatformAudit_Write @Action = 'MARK_PAID', @TenantId = @TenantId, @EntityType = 'STATEMENT', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason;
    COMMIT;
END;
