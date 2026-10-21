-- Amount fields each billing type needs (BillingType is locked, so SystemCodes are fixed):
--   FIXED -> FixedFeeAmount, RETAINER -> FixedFeeAmount (per period), NTE -> BudgetAmount.
--   HOURLY and NONBILL need nothing extra (HOURLY rates come from ProjectRate or DefaultRate).
CREATE TRIGGER crm.trg_ClientProject_ValidateBillingType
ON crm.ClientProject
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN lkp.BillingType AS bt ON bt.TenantId = i.TenantId AND bt.Id = i.BillingTypeId
        WHERE (bt.SystemCode IN ('FIXED', 'RETAINER') AND i.FixedFeeAmount IS NULL)
           OR (bt.SystemCode = 'NTE' AND i.BudgetAmount IS NULL)
    )
        THROW 50201, N'Project is missing the amount its billing type requires (Fixed Fee / Retainer: FixedFeeAmount; Not-to-exceed: BudgetAmount).', 1;
END;
