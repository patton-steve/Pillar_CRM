-- Sends a submitted bill or expense report back to DRAFT with a reason.
-- A weekly expense report (TimesheetId set) is refused: it goes back with its week (crm.usp_Timesheet_Reject).
CREATE PROCEDURE ap.usp_Bill_Reject
    @BillId     INT,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME();

    IF EXISTS (SELECT 1 FROM ap.Bill WHERE TenantId = @TenantId AND Id = @BillId AND TimesheetId IS NOT NULL)
        THROW 52312, N'This expense report goes with its timesheet week. Submit, approve or send back the week instead.', 1;

    IF NULLIF(LTRIM(@Reason), N'') IS NULL THROW 50841, N'A rejection reason is required.', 1;

    UPDATE b
    SET BillStatusId = d.Id, SubmittedAt = NULL, RejectedAt = @Now, RejectedBy = @UserId, RejectedReason = @Reason,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.Bill AS b
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId AND s.SystemCode = 'SUBMITTED'
    JOIN lkp.BillStatus AS d ON d.TenantId = b.TenantId AND d.SystemCode = 'DRAFT'
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    IF @@ROWCOUNT = 0 THROW 50842, N'Only submitted bills can be rejected.', 1;
END;
