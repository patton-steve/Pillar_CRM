-- Once issued, an invoice's content is fixed. Allowed changes: status (payments, void), AmountPaid,
-- void stamps and audit columns. Issue itself is the DRAFT -> ISSUED transition and is allowed.
CREATE TRIGGER ar.trg_Invoice_LockIssued
ON ar.Invoice
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM deleted AS d
        JOIN lkp.InvoiceStatus AS s ON s.TenantId = d.TenantId AND s.Id = d.InvoiceStatusId
        LEFT JOIN inserted AS i ON i.Id = d.Id
        WHERE s.SystemCode <> 'DRAFT'
          AND (i.Id IS NULL   -- delete
               OR EXISTS (SELECT d.ClientId, d.BillingProfileId, d.InvoiceNumber, d.InvoiceDate, d.DueDate, d.PaymentTermId,
                                 d.BillToContactId, d.BillToName, d.BillToEmail, d.BillToAddress, d.SubTotal, d.TaxAmount,
                                 d.TaxRate, d.TaxExempt, d.PoNumber, d.InvoiceNotes, d.IssuedAt
                          EXCEPT
                          SELECT i.ClientId, i.BillingProfileId, i.InvoiceNumber, i.InvoiceDate, i.DueDate, i.PaymentTermId,
                                 i.BillToContactId, i.BillToName, i.BillToEmail, i.BillToAddress, i.SubTotal, i.TaxAmount,
                                 i.TaxRate, i.TaxExempt, i.PoNumber, i.InvoiceNotes, i.IssuedAt))
    )
        THROW 50642, N'An issued invoice cannot be edited or deleted. Void it instead.', 1;
END;
