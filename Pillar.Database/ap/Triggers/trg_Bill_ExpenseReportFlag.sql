-- New expense reports (bills paid to a user) need Feature.ExpenseReports on. Checked on insert only, so turning
-- the flag off later never strands existing reports mid-approval or mid-payment.
CREATE TRIGGER ap.trg_Bill_ExpenseReportFlag
ON ap.Bill
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        CROSS APPLY admin.fn_Setting(i.TenantId, NULL, 'Feature.ExpenseReports') AS f
        WHERE i.PayeeUserId IS NOT NULL AND ISNULL(f.Value, N'0') <> N'1'
    )
        THROW 50801, N'Expense reports are not enabled for this account.', 1;
END;
