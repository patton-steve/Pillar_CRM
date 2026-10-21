-- Approves a submitted bill or expense report (SUBMITTED -> OPEN). Billable lines become available to invoice runs.
CREATE PROCEDURE ap.usp_Bill_Approve
    @BillId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME();

    UPDATE b
    SET BillStatusId = o.Id, ApprovedAt = @Now, ApprovedBy = @UserId, ModifiedAt = @Now, ModifiedBy = @UserId
    FROM ap.Bill AS b
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId AND s.SystemCode = 'SUBMITTED'
    JOIN lkp.BillStatus AS o ON o.TenantId = b.TenantId AND o.SystemCode = 'OPEN'
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    IF @@ROWCOUNT = 0 THROW 50831, N'Only submitted bills can be approved.', 1;
END;
