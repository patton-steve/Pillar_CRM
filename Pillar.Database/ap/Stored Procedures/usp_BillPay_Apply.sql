-- Applies @Amount of a bill payment to an approved bill of the same vendor or user.
-- @Amount NULL = as much as possible.
CREATE PROCEDURE ap.usp_BillPay_Apply
    @BillPayId  INT,
    @BillId     INT,
    @Amount     DECIMAL(19,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @Status VARCHAR(30), @Balance DECIMAL(19,2), @BVendor INT, @BUser INT,
            @Available DECIMAL(19,2), @PVendor INT, @PUser INT, @Found BIT = 0;

    BEGIN TRAN;

    SELECT @Status = s.SystemCode, @Balance = b.BalanceDue, @BVendor = b.VendorId, @BUser = b.PayeeUserId
    FROM ap.Bill AS b WITH (UPDLOCK)
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
    WHERE b.TenantId = @TenantId AND b.Id = @BillId;

    SELECT @Found = 1, @Available = p.UnappliedAmount, @PVendor = p.VendorId, @PUser = p.PayeeUserId
    FROM ap.BillPay AS p WITH (UPDLOCK)
    WHERE p.TenantId = @TenantId AND p.Id = @BillPayId AND p.VoidedAt IS NULL;

    IF @Status IS NULL OR @Status NOT IN ('OPEN', 'PARTIAL') THROW 50861, N'Payments can only be applied to approved, unpaid bills.', 1;
    IF @Found = 0 THROW 50862, N'Payment not found or void.', 1;
    IF ISNULL(@BVendor, -1) <> ISNULL(@PVendor, -1) OR ISNULL(@BUser, -1) <> ISNULL(@PUser, -1)
        THROW 50863, N'The payment and the bill are for different payees.', 1;

    SET @Amount = COALESCE(@Amount, CASE WHEN @Balance < @Available THEN @Balance ELSE @Available END);
    IF @Amount <= 0 THROW 50864, N'Nothing to apply.', 1;
    IF @Amount > @Balance THROW 50865, N'Amount is more than the bill balance.', 1;
    IF @Amount > @Available THROW 50866, N'Amount is more than the unapplied amount.', 1;

    INSERT INTO ap.BillPayApplication (TenantId, BillPayId, BillId, AmountApplied)
    VALUES (@TenantId, @BillPayId, @BillId, @Amount);

    EXEC ap.usp_BillApplicationTotals_Sync @BillId = @BillId, @BillPayId = @BillPayId;

    COMMIT;
END;
