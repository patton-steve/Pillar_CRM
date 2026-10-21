-- Voids an unpaid statement (IsPlatformAdmin), e.g. to correct a fee override and regenerate the month.
-- Its fees go back to unbilled (BILLED or PAID-by-zero -> ACCRUED) so the next generate picks them up; lines stay for history.
CREATE PROCEDURE admin.usp_PlatformStatement_Void
    @StatementId    INT,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 51021, N'Platform statements are voided by Pillar only.', 1;

    BEGIN TRAN;

    IF NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WITH (UPDLOCK)
                   WHERE Id = @StatementId AND Status <> 'VOID' AND AmountPaid = 0)
        THROW 51022, N'Only statements with no payments can be voided.', 1;
    IF EXISTS (SELECT 1 FROM admin.PlatformStatement AS s
               JOIN admin.PlatformStatement AS later ON later.TenantId = s.TenantId AND later.PeriodStart > s.PeriodStart AND later.Status <> 'VOID'
               WHERE s.Id = @StatementId)
        THROW 51023, N'Void the later statements first (they carry this one''s credit).', 1;

    UPDATE admin.PlatformFee
    SET PlatformStatementId = NULL,
        FeeStatus = CASE WHEN FeeStatus = 'REVERSAL' THEN FeeStatus ELSE 'ACCRUED' END
    WHERE PlatformStatementId = @StatementId;

    UPDATE admin.PlatformStatement
    SET Status = 'VOID', VoidedAt = SYSUTCDATETIME(), VoidReason = @Reason
    WHERE Id = @StatementId;

    COMMIT;
END;
