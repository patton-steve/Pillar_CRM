"""Writes rpt/Views/*.sql: the reporting views Ask Pilo queries on the pillar_ai_reader connection (handoff 24).

Each view gets an MS_Description, and so does every column; the API reads them (admin.usp_PiloCatalog) to build the
catalog it gives the model. Edit the VIEWS list below, then run:  python tools/GenerateRptViews.py
Rows are limited to the session tenant by RLS on the base tables, and each view also checks the session user's
permission (SESSION_CONTEXT UserId), so Pilo only sees what the person could see in the app.
"""
import os

USER = "CONVERT(INT, SESSION_CONTEXT(N'UserId'))"


def perm(tenant_col, code):
    return f"EXISTS (SELECT 1 FROM sec.fn_UserHasPermission({tenant_col}, {USER}, '{code}'))"


TODAY = "CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE tn.TimeZoneId AS DATE)"

ID_NOTE = "Internal id; join on it to the same column in other rpt views."

VIEWS = [
    dict(
        name="Client",
        description="One row per client (customer) of the company. Needs client.view.",
        source="""crm.Client AS c
JOIN lkp.ClientType AS ct ON ct.TenantId = c.TenantId AND ct.Id = c.ClientTypeId
JOIN lkp.ClientStatus AS cs ON cs.TenantId = c.TenantId AND cs.Id = c.ClientStatusId
LEFT JOIN lkp.Industry AS ind ON ind.TenantId = c.TenantId AND ind.Id = c.IndustryId
LEFT JOIN sec.AppUser AS am ON am.TenantId = c.TenantId AND am.Id = c.AccountManagerUserId""",
        where=f"c.DeletedAt IS NULL AND {perm('c.TenantId', 'client.view')}",
        columns=[
            ("ClientId", "c.Id", ID_NOTE),
            ("ClientCode", "c.ClientCode", "The client's short code, e.g. C00012."),
            ("ClientName", "c.Name", "The client's name (company, or the person's name for an individual)."),
            ("ClientType", "ct.Name", "Kind of client, from the company's Client types list (e.g. Company, Individual)."),
            ("ClientStatus", "cs.Name", "Client status name, e.g. Active, Inactive, Prospect."),
            ("ClientStatusCode", "cs.SystemCode", "Client status code: PROSPECT, ACTIVE or INACTIVE; use it for filtering."),
            ("Industry", "ind.Name", "The client's industry, if set."),
            ("AccountManager", "am.DisplayName", "Name of the person who manages this client, if set."),
            ("IsSample", "c.IsSample", "1 = part of the removable sample company; usually exclude these."),
            ("CreatedDate", "CAST(c.CreatedAt AS DATE)", "Date the client was added (UTC)."),
        ],
    ),
    dict(
        name="Project",
        description="One row per project. A project belongs to one client. Needs project.view.",
        source="""crm.ClientProject AS p
JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
JOIN lkp.ProjectType AS pt ON pt.TenantId = p.TenantId AND pt.Id = p.ProjectTypeId
JOIN lkp.BillingType AS bt ON bt.TenantId = p.TenantId AND bt.Id = p.BillingTypeId
JOIN lkp.ProjectStatus AS ps ON ps.TenantId = p.TenantId AND ps.Id = p.ProjectStatusId
LEFT JOIN sec.AppUser AS pm ON pm.TenantId = p.TenantId AND pm.Id = p.ProjectManagerUserId""",
        where=f"p.DeletedAt IS NULL AND {perm('p.TenantId', 'project.view')}",
        columns=[
            ("ProjectId", "p.Id", ID_NOTE),
            ("ProjectCode", "p.ProjectCode", "The project's short code."),
            ("ProjectName", "p.Name", "The project's name."),
            ("ClientId", "p.ClientId", ID_NOTE),
            ("ClientName", "c.Name", "Name of the client the project is for."),
            ("ProjectType", "pt.Name", "Kind of project, from the company's Project types list."),
            ("BillingType", "bt.Name", "How the project is billed (the company's name for it)."),
            ("BillingTypeCode", "bt.SystemCode", "Billing code: HOURLY, FIXED, RETAINER, NTE (hourly with a cap) or NONBILL (internal)."),
            ("ProjectStatus", "ps.Name", "Project status name."),
            ("ProjectStatusCode", "ps.SystemCode", "Project status code: PLANNED, OPEN, ON_HOLD or CLOSED."),
            ("ProjectManager", "pm.DisplayName", "Name of the project manager, if set."),
            ("StartDate", "p.StartDate", "Planned start date."),
            ("EndDate", "p.EndDate", "Planned end date."),
            ("BudgetHours", "p.BudgetHours", "Hours budgeted for the project, if set."),
            ("BudgetAmount", "CONVERT(DECIMAL(19,2), p.BudgetAmount)", "Money budget or not-to-exceed cap, in the company's currency, if set."),
            ("FixedFeeAmount", "CONVERT(DECIMAL(19,2), p.FixedFeeAmount)", "Fixed fee total, or the retainer amount per period, if the project uses one."),
            ("CreatedDate", "CAST(p.CreatedAt AS DATE)", "Date the project was added (UTC)."),
        ],
    ),
    dict(
        name="Task",
        description="One row per task. A task belongs to one project. TaskKey looks like WEB-42. Needs project.view.",
        source="""crm.ClientTask AS t
JOIN crm.ClientProject AS p ON p.TenantId = t.TenantId AND p.Id = t.ProjectId
JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
JOIN lkp.TaskStatus AS ts ON ts.TenantId = t.TenantId AND ts.Id = t.TaskStatusId
LEFT JOIN lkp.TaskType AS tt ON tt.TenantId = t.TenantId AND tt.Id = t.TaskTypeId
LEFT JOIN lkp.TaskPriority AS tp ON tp.TenantId = t.TenantId AND tp.Id = t.TaskPriorityId
LEFT JOIN sec.AppUser AS a ON a.TenantId = t.TenantId AND a.Id = t.AssignedUserId""",
        where=f"t.DeletedAt IS NULL AND p.DeletedAt IS NULL AND {perm('t.TenantId', 'project.view')}",
        columns=[
            ("TaskId", "t.Id", ID_NOTE),
            ("TaskKey", "t.TaskKey", "The task's key, e.g. WEB-42."),
            ("TaskTitle", "t.Title", "The task's title."),
            ("ProjectId", "t.ProjectId", ID_NOTE),
            ("ProjectName", "p.Name", "Name of the task's project."),
            ("ClientId", "p.ClientId", ID_NOTE),
            ("ClientName", "c.Name", "Name of the client the task's project is for."),
            ("TaskType", "tt.Name", "Kind of task, from the company's Task types list."),
            ("TaskStatus", "ts.Name", "Task status name."),
            ("TaskStatusCode", "ts.SystemCode", "Task status code: TODO, IN_PROGRESS, BLOCKED, DONE or CANCELLED."),
            ("Priority", "tp.Name", "Task priority name, if set."),
            ("AssignedUserId", "t.AssignedUserId", ID_NOTE),
            ("AssignedTo", "a.DisplayName", "Name of the person the task is assigned to, if anyone."),
            ("EstimatedHours", "t.EstimatedHours", "Estimated hours, if set."),
            ("StartDate", "t.StartDate", "Planned start date."),
            ("DueDate", "t.DueDate", "Due date, if set."),
            ("CompletedDate", "CAST(t.CompletedAt AS DATE)", "Date the task was marked done (UTC), if it is done."),
            ("IsBillable", "t.IsBillable", "1 = time on this task is billable by default."),
            ("CreatedDate", "CAST(t.CreatedAt AS DATE)", "Date the task was added (UTC)."),
        ],
    ),
    dict(
        name="TimeEntry",
        description="One row per time entry. The person's own time, or everyone's with time.view_all. Rate and BillableAmount "
                    "are NULL unless the person can see invoices or set rates.",
        source=f"""crm.TimeEntry AS e
JOIN crm.ClientTask AS t ON t.TenantId = e.TenantId AND t.Id = e.TaskId
JOIN crm.ClientProject AS p ON p.TenantId = e.TenantId AND p.Id = e.ProjectId
JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
JOIN crm.Timesheet AS sh ON sh.TenantId = e.TenantId AND sh.Id = e.TimesheetId
JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
JOIN sec.AppUser AS u ON u.TenantId = e.TenantId AND u.Id = e.AppUserId
LEFT JOIN ar.InvoiceEntry AS ie ON ie.TenantId = e.TenantId AND ie.Id = e.InvoiceEntryId
LEFT JOIN ar.Invoice AS i ON i.TenantId = ie.TenantId AND i.Id = ie.InvoiceId
CROSS APPLY (SELECT CONVERT(BIT, IIF({perm('e.TenantId', 'invoice.view')} OR {perm('e.TenantId', 'project.rates')}, 1, 0)) AS SeeMoney) AS m""",
        where=f"e.DeletedAt IS NULL AND (e.AppUserId = {USER} OR {perm('e.TenantId', 'time.view_all')})",
        columns=[
            ("TimeEntryId", "e.Id", ID_NOTE),
            ("WorkDate", "e.WorkDate", "Date the work was done."),
            ("WeekStart", "sh.WeekStart", "First day of the timesheet week the entry is on."),
            ("PersonId", "e.AppUserId", ID_NOTE),
            ("Person", "u.DisplayName", "Name of the person whose time it is."),
            ("ClientId", "p.ClientId", ID_NOTE),
            ("ClientName", "c.Name", "Client name."),
            ("ProjectId", "e.ProjectId", ID_NOTE),
            ("ProjectName", "p.Name", "Project name."),
            ("TaskId", "e.TaskId", ID_NOTE),
            ("TaskKey", "t.TaskKey", "Task key, e.g. WEB-42."),
            ("TaskTitle", "t.Title", "Task title."),
            ("Hours", "CONVERT(DECIMAL(9,2), e.Hours)", "Hours billed (after the company's rounding). NULL while a timer is running."),
            ("EnteredHours", "CONVERT(DECIMAL(9,2), e.EnteredMinutes / 60.0)", "Hours as the person entered them, before rounding."),
            ("IsBillable", "e.IsBillable", "1 = billable to the client."),
            ("Rate", "IIF(m.SeeMoney = 1, CONVERT(DECIMAL(19,2), e.RateApplied), NULL)", "Hourly billing rate applied, in the company's currency; NULL when hidden."),
            ("BillableAmount", "IIF(m.SeeMoney = 1, e.AmountBillable, NULL)", "Hours x rate for billable time (0 when not billable); NULL when hidden."),
            ("Status", "s.Name", "Time entry status name."),
            ("StatusCode", "s.SystemCode", "Status code: DRAFT, SUBMITTED, APPROVED, INVOICED or WRITTEN_OFF."),
            ("Description", "e.Description", "What was done (prints on the invoice)."),
            ("InvoiceNumber", "i.InvoiceNumber", "Number of the issued invoice the time is billed on; NULL if not invoiced or still on a draft."),
        ],
    ),
    dict(
        name="Expense",
        description="One row per expense line on people's expense reports (not vendor bills). The person's own, or everyone's "
                    "with ap.view. Voided reports are left out.",
        source="""ap.BillLine AS l
JOIN ap.Bill AS b ON b.TenantId = l.TenantId AND b.Id = l.BillId
JOIN lkp.BillStatus AS bs ON bs.TenantId = b.TenantId AND bs.Id = b.BillStatusId
JOIN lkp.ExpenseCategory AS ec ON ec.TenantId = l.TenantId AND ec.Id = l.ExpenseCategoryId
JOIN sec.AppUser AS u ON u.TenantId = b.TenantId AND u.Id = b.PayeeUserId
LEFT JOIN crm.ClientProject AS p ON p.TenantId = l.TenantId AND p.Id = l.ProjectId
LEFT JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
LEFT JOIN crm.ClientTask AS t ON t.TenantId = l.TenantId AND t.Id = l.TaskId""",
        where=f"b.PayeeUserId IS NOT NULL AND b.VoidedAt IS NULL AND (b.PayeeUserId = {USER} OR {perm('b.TenantId', 'ap.view')})",
        columns=[
            ("ExpenseLineId", "l.Id", ID_NOTE),
            ("ExpenseDate", "l.ExpenseDate", "Date of the expense."),
            ("PersonId", "b.PayeeUserId", ID_NOTE),
            ("Person", "u.DisplayName", "Name of the person who spent the money."),
            ("Category", "ec.Name", "Expense category, e.g. Mileage, Meals, Supplies."),
            ("Merchant", "l.Merchant", "Where the money was spent, if recorded."),
            ("Description", "l.Description", "What the expense was for."),
            ("Quantity", "l.Quantity", "Units, e.g. miles for mileage; 1 for most expenses."),
            ("Amount", "l.Amount", "Amount to reimburse, in the company's currency."),
            ("IsBillable", "l.IsBillable", "1 = rebilled to the client."),
            ("BillableAmount", "l.BillableAmount", "Amount rebilled to the client, including markup."),
            ("ClientId", "p.ClientId", ID_NOTE),
            ("ClientName", "c.Name", "Client the expense is for, if any."),
            ("ProjectId", "l.ProjectId", ID_NOTE),
            ("ProjectName", "p.Name", "Project the expense is for, if any."),
            ("TaskKey", "t.TaskKey", "Task the expense is for, if any."),
            ("ReportNumber", "b.BillNumber", "Expense report number, e.g. EXP-00012."),
            ("ReportStatus", "bs.Name", "Expense report status name."),
            ("ReportStatusCode", "bs.SystemCode", "Report status code: DRAFT, SUBMITTED, OPEN (approved, unpaid), PARTIAL or PAID."),
            ("IsInvoiced", "CONVERT(BIT, IIF(l.InvoiceEntryId IS NULL, 0, 1))", "1 = already put on a client invoice."),
        ],
    ),
    dict(
        name="Invoice",
        description="One row per client invoice, drafts and voids included (filter on StatusCode). Needs invoice.view.",
        source="""ar.Invoice AS i
JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
JOIN admin.Tenant AS tn ON tn.Id = i.TenantId""",
        where=perm('i.TenantId', 'invoice.view'),
        columns=[
            ("InvoiceId", "i.Id", ID_NOTE),
            ("InvoiceNumber", "i.InvoiceNumber", "Invoice number; NULL on drafts (numbers are given at issue)."),
            ("ClientId", "i.ClientId", ID_NOTE),
            ("ClientName", "COALESCE(i.ClientName, c.Name)", "Client name as printed on the invoice."),
            ("Status", "s.Name", "Invoice status name."),
            ("StatusCode", "s.SystemCode", "Status code: DRAFT, ISSUED, PARTIAL, PAID or VOID. Revenue usually means ISSUED, PARTIAL and PAID."),
            ("InvoiceDate", "i.InvoiceDate", "Invoice date (set at issue)."),
            ("DueDate", "i.DueDate", "Payment due date."),
            ("PeriodStart", "i.PeriodStart", "Start of the billing period covered, if any."),
            ("PeriodEnd", "i.PeriodEnd", "End of the billing period covered, if any."),
            ("PoNumber", "i.PoNumber", "Client's purchase order number, if any."),
            ("SubTotal", "i.SubTotal", "Total before tax, in the company's currency."),
            ("TaxAmount", "i.TaxAmount", "Sales tax."),
            ("Total", "i.Total", "Total including tax."),
            ("AmountPaid", "i.AmountPaid", "Paid or credited so far."),
            ("BalanceDue", "i.BalanceDue", "Still owed."),
            ("DaysPastDue", f"IIF((s.SystemCode = 'ISSUED' OR s.SystemCode = 'PARTIAL') AND i.BalanceDue > 0 AND i.DueDate < {TODAY}, DATEDIFF(DAY, i.DueDate, {TODAY}), 0)",
             "Days since the due date for an unpaid issued invoice, else 0 (in the company's time zone)."),
            ("IssuedDate", "CAST(i.IssuedAt AS DATE)", "Date the invoice was issued (UTC)."),
            ("VoidedDate", "CAST(i.VoidedAt AS DATE)", "Date the invoice was voided, if it was."),
        ],
    ),
    dict(
        name="InvoiceLine",
        description="One row per invoice line, for revenue by project, task or line type. Needs invoice.view.",
        source="""ar.InvoiceEntry AS ie
JOIN ar.Invoice AS i ON i.TenantId = ie.TenantId AND i.Id = ie.InvoiceId
JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
JOIN lkp.InvoiceLineType AS lt ON lt.TenantId = ie.TenantId AND lt.Id = ie.LineTypeId
LEFT JOIN crm.ClientProject AS p ON p.TenantId = ie.TenantId AND p.Id = ie.ProjectId
LEFT JOIN crm.ClientTask AS t ON t.TenantId = ie.TenantId AND t.Id = ie.TaskId""",
        where=perm('ie.TenantId', 'invoice.view'),
        columns=[
            ("InvoiceLineId", "ie.Id", ID_NOTE),
            ("InvoiceId", "ie.InvoiceId", ID_NOTE),
            ("InvoiceNumber", "i.InvoiceNumber", "Invoice number; NULL on drafts."),
            ("InvoiceDate", "i.InvoiceDate", "Invoice date."),
            ("InvoiceStatusCode", "s.SystemCode", "Invoice status code: DRAFT, ISSUED, PARTIAL, PAID or VOID."),
            ("ClientId", "i.ClientId", ID_NOTE),
            ("ClientName", "c.Name", "Client name."),
            ("ProjectId", "ie.ProjectId", ID_NOTE),
            ("ProjectName", "p.Name", "Project the line bills, if any."),
            ("TaskKey", "t.TaskKey", "Task the line bills, if any."),
            ("LineType", "lt.Name", "Line type name."),
            ("LineTypeCode", "lt.SystemCode", "Line type code: TIME, RETAINER, FIXED_FEE, EXPENSE, ADJUSTMENT or DISCOUNT."),
            ("Description", "ie.Description", "Line description as printed."),
            ("Amount", "ie.Amount", "Line amount before tax, in the company's currency (negative for discounts)."),
            ("ServicePeriodStart", "ie.ServicePeriodStart", "Start of the service period the line covers, if any."),
            ("ServicePeriodEnd", "ie.ServicePeriodEnd", "End of the service period the line covers, if any."),
        ],
    ),
    dict(
        name="Payment",
        description="One row per client payment received, voided ones included (see IsVoided). Needs invoice.view.",
        source="""ar.InvoicePay AS pay
JOIN crm.Client AS c ON c.TenantId = pay.TenantId AND c.Id = pay.ClientId
JOIN lkp.PaymentMethod AS pm ON pm.TenantId = pay.TenantId AND pm.Id = pay.PaymentMethodId""",
        where=perm('pay.TenantId', 'invoice.view'),
        columns=[
            ("PaymentId", "pay.Id", ID_NOTE),
            ("PaymentDate", "pay.PaymentDate", "Date the payment was received."),
            ("ClientId", "pay.ClientId", ID_NOTE),
            ("ClientName", "c.Name", "Client who paid."),
            ("PaymentMethod", "pm.Name", "How they paid, e.g. Check, ACH, Card."),
            ("ReferenceNumber", "pay.ReferenceNumber", "Check number or transaction reference."),
            ("Amount", "pay.Amount", "Amount received, in the company's currency."),
            ("AmountApplied", "pay.AmountApplied", "Part applied to invoices."),
            ("AmountRefunded", "pay.AmountRefunded", "Part refunded to the client."),
            ("UnappliedAmount", "pay.UnappliedAmount", "Part not yet applied (client credit)."),
            ("IsVoided", "CONVERT(BIT, IIF(pay.VoidedAt IS NULL, 0, 1))", "1 = the payment was voided; usually exclude."),
        ],
    ),
    dict(
        name="ArAging",
        description="Accounts receivable aging: one row per issued invoice with a balance, bucketed by days past due "
                    "as of today in the company's time zone. Needs invoice.view.",
        source="""ar.Invoice AS i
JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
JOIN admin.Tenant AS tn ON tn.Id = i.TenantId
CROSS APPLY (SELECT IIF(i.DueDate < """ + TODAY + """, DATEDIFF(DAY, i.DueDate, """ + TODAY + """), 0) AS Days) AS d""",
        where=f"(s.SystemCode = 'ISSUED' OR s.SystemCode = 'PARTIAL') AND i.BalanceDue > 0 AND {perm('i.TenantId', 'invoice.view')}",
        columns=[
            ("InvoiceId", "i.Id", ID_NOTE),
            ("InvoiceNumber", "i.InvoiceNumber", "Invoice number."),
            ("ClientId", "i.ClientId", ID_NOTE),
            ("ClientName", "COALESCE(i.ClientName, c.Name)", "Client name."),
            ("InvoiceDate", "i.InvoiceDate", "Invoice date."),
            ("DueDate", "i.DueDate", "Due date."),
            ("Total", "i.Total", "Invoice total, in the company's currency."),
            ("BalanceDue", "i.BalanceDue", "Still owed."),
            ("DaysPastDue", "d.Days", "Days past the due date; 0 when not yet due."),
            ("AgingBucket", "CASE WHEN d.Days = 0 THEN N'Current' WHEN d.Days <= 30 THEN N'1-30' WHEN d.Days <= 60 THEN N'31-60' "
                            "WHEN d.Days <= 90 THEN N'61-90' ELSE N'Over 90' END",
             "Aging bucket: Current, 1-30, 31-60, 61-90 or Over 90 days past due."),
            ("AgingBucketOrder", "CASE WHEN d.Days = 0 THEN 0 WHEN d.Days <= 30 THEN 1 WHEN d.Days <= 60 THEN 2 WHEN d.Days <= 90 THEN 3 ELSE 4 END",
             "Sort order of AgingBucket, 0 (Current) to 4 (Over 90)."),
        ],
    ),
    dict(
        name="Bill",
        description="One row per bill the company owes: vendor bills and people's expense reports (IsExpenseReport). "
                    "Voided ones included (StatusCode VOID). Needs ap.view.",
        source="""ap.Bill AS b
JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
JOIN admin.Tenant AS tn ON tn.Id = b.TenantId
LEFT JOIN ap.Vendor AS v ON v.TenantId = b.TenantId AND v.Id = b.VendorId
LEFT JOIN sec.AppUser AS u ON u.TenantId = b.TenantId AND u.Id = b.PayeeUserId""",
        where=perm('b.TenantId', 'ap.view'),
        columns=[
            ("BillId", "b.Id", ID_NOTE),
            ("BillNumber", "b.BillNumber", "The company's own bill number, e.g. BILL-00031 or EXP-00012."),
            ("IsExpenseReport", "CONVERT(BIT, IIF(b.PayeeUserId IS NULL, 0, 1))", "1 = a person's expense report; 0 = a vendor bill."),
            ("VendorId", "b.VendorId", ID_NOTE),
            ("PayeeName", "COALESCE(v.Name, u.DisplayName)", "Vendor name, or the person for an expense report."),
            ("VendorInvoiceNumber", "b.VendorInvoiceNumber", "The vendor's own invoice number, if any."),
            ("BillDate", "b.BillDate", "Bill date."),
            ("DueDate", "b.DueDate", "Payment due date."),
            ("Status", "s.Name", "Bill status name."),
            ("StatusCode", "s.SystemCode", "Status code: DRAFT, SUBMITTED, OPEN (approved, unpaid), PARTIAL, PAID or VOID."),
            ("Description", "b.Description", "What the bill is for."),
            ("SubTotal", "b.SubTotal", "Total before tax, in the company's currency."),
            ("TaxAmount", "b.TaxAmount", "Tax."),
            ("Total", "b.Total", "Total including tax."),
            ("AmountPaid", "b.AmountPaid", "Paid so far."),
            ("BalanceDue", "b.BalanceDue", "Still owed."),
            ("DaysPastDue", f"IIF((s.SystemCode = 'OPEN' OR s.SystemCode = 'PARTIAL') AND b.BalanceDue > 0 AND b.DueDate < {TODAY}, DATEDIFF(DAY, b.DueDate, {TODAY}), 0)",
             "Days since the due date for an unpaid approved bill, else 0."),
        ],
    ),
    dict(
        name="BillPayment",
        description="One row per payment the company made on bills or expense reports, voided ones included. Needs ap.view.",
        source="""ap.BillPay AS bp
JOIN lkp.PaymentMethod AS pm ON pm.TenantId = bp.TenantId AND pm.Id = bp.PaymentMethodId
LEFT JOIN ap.Vendor AS v ON v.TenantId = bp.TenantId AND v.Id = bp.VendorId
LEFT JOIN sec.AppUser AS u ON u.TenantId = bp.TenantId AND u.Id = bp.PayeeUserId""",
        where=perm('bp.TenantId', 'ap.view'),
        columns=[
            ("BillPaymentId", "bp.Id", ID_NOTE),
            ("PaymentDate", "bp.PaymentDate", "Date paid."),
            ("VendorId", "bp.VendorId", ID_NOTE),
            ("PayeeName", "COALESCE(v.Name, u.DisplayName)", "Vendor paid, or the person reimbursed."),
            ("PaymentMethod", "pm.Name", "How it was paid."),
            ("ReferenceNumber", "bp.ReferenceNumber", "Check number or transaction reference."),
            ("Amount", "bp.Amount", "Amount paid, in the company's currency."),
            ("AmountApplied", "bp.AmountApplied", "Part applied to bills."),
            ("UnappliedAmount", "bp.UnappliedAmount", "Part not yet applied."),
            ("IsVoided", "CONVERT(BIT, IIF(bp.VoidedAt IS NULL, 0, 1))", "1 = the payment was voided; usually exclude."),
        ],
    ),
    dict(
        name="ApAging",
        description="Accounts payable aging: one row per approved bill or expense report with a balance, bucketed by days "
                    "past due as of today in the company's time zone. Needs ap.view.",
        source="""ap.Bill AS b
JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
JOIN admin.Tenant AS tn ON tn.Id = b.TenantId
LEFT JOIN ap.Vendor AS v ON v.TenantId = b.TenantId AND v.Id = b.VendorId
LEFT JOIN sec.AppUser AS u ON u.TenantId = b.TenantId AND u.Id = b.PayeeUserId
CROSS APPLY (SELECT IIF(b.DueDate < """ + TODAY + """, DATEDIFF(DAY, b.DueDate, """ + TODAY + """), 0) AS Days) AS d""",
        where=f"(s.SystemCode = 'OPEN' OR s.SystemCode = 'PARTIAL') AND b.BalanceDue > 0 AND {perm('b.TenantId', 'ap.view')}",
        columns=[
            ("BillId", "b.Id", ID_NOTE),
            ("BillNumber", "b.BillNumber", "The company's own bill number."),
            ("IsExpenseReport", "CONVERT(BIT, IIF(b.PayeeUserId IS NULL, 0, 1))", "1 = a person's expense report; 0 = a vendor bill."),
            ("PayeeName", "COALESCE(v.Name, u.DisplayName)", "Vendor, or the person for an expense report."),
            ("BillDate", "b.BillDate", "Bill date."),
            ("DueDate", "b.DueDate", "Due date."),
            ("Total", "b.Total", "Bill total, in the company's currency."),
            ("BalanceDue", "b.BalanceDue", "Still owed."),
            ("DaysPastDue", "d.Days", "Days past the due date; 0 when not yet due."),
            ("AgingBucket", "CASE WHEN d.Days = 0 THEN N'Current' WHEN d.Days <= 30 THEN N'1-30' WHEN d.Days <= 60 THEN N'31-60' "
                            "WHEN d.Days <= 90 THEN N'61-90' ELSE N'Over 90' END",
             "Aging bucket: Current, 1-30, 31-60, 61-90 or Over 90 days past due."),
            ("AgingBucketOrder", "CASE WHEN d.Days = 0 THEN 0 WHEN d.Days <= 30 THEN 1 WHEN d.Days <= 60 THEN 2 WHEN d.Days <= 90 THEN 3 ELSE 4 END",
             "Sort order of AgingBucket, 0 (Current) to 4 (Over 90)."),
        ],
    ),
]


def q(text):
    return text.replace("'", "''")


def render(v):
    width = max(len(c[0]) for c in v["columns"])
    cols = ",\n".join(f"    {expr} AS {name}" for name, expr, _ in v["columns"])
    lines = [
        "-- Generated by tools/GenerateRptViews.py; edit the generator, not this file.",
        f"-- {v['description']}",
        f"CREATE VIEW rpt.{v['name']}",
        "AS",
        "SELECT",
        cols,
        "FROM " + v["source"].replace("\n", "\n"),
        "WHERE " + v["where"] + ";",
        "GO",
        f"EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'{q(v['description'])}',",
        f"    @level0type = N'SCHEMA', @level0name = N'rpt', @level1type = N'VIEW', @level1name = N'{v['name']}';",
    ]
    for name, _, desc in v["columns"]:
        lines += [
            "GO",
            f"EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'{q(desc)}',",
            f"    @level0type = N'SCHEMA', @level0name = N'rpt', @level1type = N'VIEW', @level1name = N'{v['name']}',",
            f"    @level2type = N'COLUMN', @level2name = N'{name}';",
        ]
    return "\n".join(lines) + "\n"


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rpt", "Views")
    os.makedirs(root, exist_ok=True)
    for v in VIEWS:
        with open(os.path.join(root, v["name"] + ".sql"), "w", newline="\n") as f:
            f.write(render(v))
    print(f"wrote {len(VIEWS)} views to rpt/Views")


if __name__ == "__main__":
    main()
