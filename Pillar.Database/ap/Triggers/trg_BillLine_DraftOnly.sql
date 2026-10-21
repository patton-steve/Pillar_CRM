-- Bill lines can only be added, changed or removed while the bill is a draft.
-- The one exception is InvoiceEntryId, which invoice runs set and clear when rebilling expenses.
CREATE TRIGGER ap.trg_BillLine_DraftOnly
ON ap.BillLine
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM (SELECT TenantId, BillId FROM inserted UNION SELECT TenantId, BillId FROM deleted) AS x
        JOIN ap.Bill AS b ON b.TenantId = x.TenantId AND b.Id = x.BillId
        JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
        WHERE s.SystemCode <> 'DRAFT'
    )
    AND EXISTS (   -- anything other than an InvoiceEntryId-only update
        SELECT d.Id, d.BillId, d.LineNumber, d.ExpenseDate, d.ExpenseCategoryId, d.Description, d.Quantity, d.UnitPrice,
               d.Amount, d.ProjectId, d.TaskId, d.IsBillable, d.MarkupPercent
        FROM deleted AS d
        EXCEPT
        SELECT i.Id, i.BillId, i.LineNumber, i.ExpenseDate, i.ExpenseCategoryId, i.Description, i.Quantity, i.UnitPrice,
               i.Amount, i.ProjectId, i.TaskId, i.IsBillable, i.MarkupPercent
        FROM inserted AS i
        UNION ALL
        SELECT i.Id, i.BillId, i.LineNumber, i.ExpenseDate, i.ExpenseCategoryId, i.Description, i.Quantity, i.UnitPrice,
               i.Amount, i.ProjectId, i.TaskId, i.IsBillable, i.MarkupPercent
        FROM inserted AS i
        WHERE NOT EXISTS (SELECT 1 FROM deleted AS d WHERE d.Id = i.Id)
    )
        THROW 50802, N'Lines of a submitted, approved or void bill cannot be changed.', 1;
END;
