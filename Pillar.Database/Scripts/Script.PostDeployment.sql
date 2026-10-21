/*
Post-deployment seed: Pillar-owned rows (SystemCode and lkp.Default* masters).
Runs after every publish and is rerunnable. It inserts missing rows and updates
Pillar-owned columns. It never deletes, and never touches tenant lists; use
lkp.usp_SyncTenantLookups to push new defaults to tenants.
*/
SET NOCOUNT ON;
EXEC sp_set_session_context N'IsPlatformAdmin', 1;

------------------------------------------------------------------ SystemCode
MERGE lkp.SystemCode AS t
USING (VALUES
    ('ClientType',   'BUSINESS',   N'Organization: company name fields', 10),
    ('ClientType',   'INDIVIDUAL', N'Person: first and last name fields', 20),
    ('ClientStatus', 'PROSPECT',   N'Projects allowed; no time entry or invoices', 10),
    ('ClientStatus', 'ACTIVE',     N'All activity allowed', 20),
    ('ClientStatus', 'INACTIVE',   N'No new projects, time or invoices; payments on open balances still accepted', 30),
    ('BillingType',      'HOURLY',      N'Billed from approved time at resolved rates', 10),
    ('BillingType',      'FIXED',       N'Fixed total fee; time tracked for profitability', 20),
    ('BillingType',      'RETAINER',    N'Fixed amount each invoice period', 30),
    ('BillingType',      'NTE',         N'Hourly, capped at BudgetAmount', 40),
    ('BillingType',      'NONBILL',     N'Internal or non-billable work; never invoiced', 50),
    ('ProjectStatus',    'PLANNED',     N'Set up only; no time entry', 10),
    ('ProjectStatus',    'OPEN',        N'All activity allowed', 20),
    ('ProjectStatus',    'ON_HOLD',     N'No time entry; invoicing of approved time allowed', 30),
    ('ProjectStatus',    'CLOSED',      N'No time entry; final invoice of approved time allowed', 40),
    ('InvoiceFrequency', 'WEEKLY',      N'Ready to invoice weekly', 10),
    ('InvoiceFrequency', 'BIWEEKLY',    N'Ready to invoice every two weeks', 20),
    ('InvoiceFrequency', 'SEMIMONTHLY', N'Ready to invoice on the 15th and month end', 30),
    ('InvoiceFrequency', 'MONTHLY',     N'Ready to invoice at month end', 40),
    ('InvoiceFrequency', 'MILESTONE',   N'Invoiced when a milestone is marked complete', 50),
    ('InvoiceFrequency', 'ONDEMAND',    N'Invoiced manually', 60),
    ('TaskStatus',       'TODO',        N'Not started; time allowed', 10),
    ('TaskStatus',       'IN_PROGRESS', N'Being worked; time allowed', 20),
    ('TaskStatus',       'BLOCKED',     N'Waiting on something; time allowed', 30),
    ('TaskStatus',       'DONE',        N'Complete; no new time; stamps CompletedAt', 40),
    ('TaskStatus',       'CANCELLED',   N'Will not be done; no new time', 50),
    ('TimeEntryStatus',  'DRAFT',       N'Being entered; editable by its owner', 10),
    ('TimeEntryStatus',  'SUBMITTED',   N'Waiting for approval', 20),
    ('TimeEntryStatus',  'APPROVED',    N'Approved; rate frozen; ready to invoice', 30),
    ('TimeEntryStatus',  'INVOICED',    N'On an invoice; locked', 40),
    ('TimeEntryStatus',  'WRITTEN_OFF', N'Approved but will never be billed', 50),
    ('InvoiceStatus',    'DRAFT',       N'Editable, unnumbered; no fee', 10),
    ('InvoiceStatus',    'ISSUED',      N'Numbered and sent; content locked; fee accrued', 20),
    ('InvoiceStatus',    'PARTIAL',     N'Issued and partly paid', 30),
    ('InvoiceStatus',    'PAID',        N'Issued and fully paid', 40),
    ('InvoiceStatus',    'VOID',        N'Cancelled after issue; fee reversed; time released', 50),
    ('InvoiceLineType',  'TIME',        N'Hours x rate from approved time', 10),
    ('InvoiceLineType',  'RETAINER',    N'Monthly retainer amount', 20),
    ('InvoiceLineType',  'FIXED_FEE',   N'Fixed-fee billing', 30),
    ('InvoiceLineType',  'EXPENSE',     N'Reimbursable expense', 40),
    ('InvoiceLineType',  'ADJUSTMENT',  N'Correction or not-to-exceed limit', 50),
    ('InvoiceLineType',  'DISCOUNT',    N'Discount (negative amount)', 60),
    ('BillStatus',       'DRAFT',       N'Being entered; editable', 10),
    ('BillStatus',       'SUBMITTED',   N'Waiting for approval', 20),
    ('BillStatus',       'OPEN',        N'Approved and unpaid; billable lines can be invoiced', 30),
    ('BillStatus',       'PARTIAL',     N'Partly paid', 40),
    ('BillStatus',       'PAID',        N'Fully paid', 50),
    ('BillStatus',       'VOID',        N'Cancelled', 60),
    ('TimesheetStatus',  'OPEN',        N'Has unsubmitted time (or none yet)', 10),
    ('TimesheetStatus',  'SUBMITTED',   N'Waiting for approval', 20),
    ('TimesheetStatus',  'APPROVED',    N'All time approved', 30),
    ('TimesheetStatus',  'REJECTED',    N'Time sent back with a reason', 40)
) AS s (LookupName, SystemCode, Description, SortOrder)
ON t.LookupName = s.LookupName AND t.SystemCode = s.SystemCode
WHEN MATCHED THEN UPDATE SET Description = s.Description, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (LookupName, SystemCode, Description, SortOrder)
    VALUES (s.LookupName, s.SystemCode, s.Description, s.SortOrder);

------------------------------------------------------------------ Defaults
-- Code is the stable key. Name and SortOrder are refreshed on the master only.
MERGE lkp.DefaultClientType AS t
USING (VALUES
    (N'BUS', N'Business',   10, 'BUSINESS',   1),
    (N'IND', N'Individual', 20, 'INDIVIDUAL', 0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault);

MERGE lkp.DefaultClientStatus AS t
USING (VALUES
    (N'PROSPECT', N'Prospect', 10, 'PROSPECT', 0),
    (N'ACTIVE',   N'Active',   20, 'ACTIVE',   1),
    (N'HOLD',     N'On Hold',  30, 'INACTIVE', 0),
    (N'INACTIVE', N'Inactive', 40, 'INACTIVE', 0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault);

MERGE lkp.DefaultPaymentTerm AS t
USING (VALUES
    (N'DUE', N'Due on Receipt', 10, 0,  0),
    (N'N15', N'Net 15',         20, 15, 0),
    (N'N30', N'Net 30',         30, 30, 1),
    (N'N45', N'Net 45',         40, 45, 0)
) AS s (Code, Name, SortOrder, DueDays, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, DueDays = s.DueDays, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, DueDays, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.DueDays, s.IsDefault);

MERGE lkp.DefaultIndustry AS t
USING (VALUES
    (N'CONSULT', N'Consulting',            10),
    (N'TECH',    N'Technology',            20),
    (N'MFG',     N'Manufacturing',         30),
    (N'RETAIL',  N'Retail',                40),
    (N'HEALTH',  N'Healthcare',            50),
    (N'FIN',     N'Financial Services',    60),
    (N'CONSTR',  N'Construction',          70),
    (N'PROF',    N'Professional Services', 80),
    (N'GOV',     N'Government',            90),
    (N'NONPROF', N'Nonprofit',            100),
    (N'OTHER',   N'Other',                999)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

MERGE lkp.DefaultAddressType AS t
USING (VALUES
    (N'BILL', N'Billing',  10),
    (N'PHYS', N'Physical', 20),
    (N'MAIL', N'Mailing',  30)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

MERGE lkp.DefaultContactRole AS t
USING (VALUES
    (N'PRIMARY', N'Primary',   10),
    (N'BILLING', N'Billing',   20),
    (N'TECH',    N'Technical', 30),
    (N'EXEC',    N'Executive', 40),
    (N'OTHER',   N'Other',     99)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

MERGE lkp.DefaultBillingType AS t
USING (VALUES
    (N'HOURLY',   N'Hourly',        10, 'HOURLY',   1),
    (N'FIXED',    N'Fixed Fee',     20, 'FIXED',    0),
    (N'RETAINER', N'Retainer',      30, 'RETAINER', 0),
    (N'NTE',      N'Not-to-Exceed', 40, 'NTE',      0),
    (N'NONBILL',  N'Non-billable',  50, 'NONBILL',  0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault, IsLocked = 1
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault, IsLocked) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault, 1);

MERGE lkp.DefaultProjectStatus AS t
USING (VALUES
    (N'PLANNED', N'Planned', 10, 'PLANNED', 0),
    (N'OPEN',    N'Open',    20, 'OPEN',    1),
    (N'HOLD',    N'On Hold', 30, 'ON_HOLD', 0),
    (N'CLOSED',  N'Closed',  40, 'CLOSED',  0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault);

MERGE lkp.DefaultInvoiceFrequency AS t
USING (VALUES
    (N'WEEKLY',  N'Weekly',       10, 'WEEKLY',      0),
    (N'BIWEEKLY',N'Biweekly',     20, 'BIWEEKLY',    0),
    (N'SEMIMO',  N'Semi-monthly', 30, 'SEMIMONTHLY', 0),
    (N'MONTHLY', N'Monthly',      40, 'MONTHLY',     1),
    (N'MILE',    N'Milestone',    50, 'MILESTONE',   0),
    (N'ONDEMAND',N'On Demand',    60, 'ONDEMAND',    0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault);

MERGE lkp.DefaultTaskType AS t
USING (VALUES
    (N'CONSULT', N'Consulting',         10),
    (N'DEV',     N'Development',        20),
    (N'PM',      N'Project Management', 30),
    (N'MEET',    N'Meeting',            40),
    (N'TRAVEL',  N'Travel',             50),
    (N'ADMIN',   N'Administrative',     60),
    (N'OTHER',   N'Other',              99)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

MERGE lkp.DefaultTaskStatus AS t
USING (VALUES
    (N'TODO',     N'To Do',       10, 'TODO',        1),
    (N'INPROG',   N'In Progress', 20, 'IN_PROGRESS', 0),
    (N'BLOCKED',  N'Blocked',     30, 'BLOCKED',     0),
    (N'DONE',     N'Done',        40, 'DONE',        0),
    (N'CANCEL',   N'Cancelled',   50, 'CANCELLED',   0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault);

MERGE lkp.DefaultTaskPriority AS t
USING (VALUES
    (N'LOW',    N'Low',    10, 0),
    (N'MED',    N'Medium', 20, 1),
    (N'HIGH',   N'High',   30, 0),
    (N'URGENT', N'Urgent', 40, 0)
) AS s (Code, Name, SortOrder, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.IsDefault);

-- after DefaultBillingType: each type's default billing type is matched by code
MERGE lkp.DefaultProjectType AS t
USING (
    SELECT v.Code, v.Name, v.SortOrder, v.KeyPrefix, v.IsDefault, bt.Id AS DefaultBillingTypeId
    FROM (VALUES
        (N'CON', N'Consulting',             10, 'CON', N'HOURLY',   1),
        (N'DEV', N'Development',            20, 'DEV', N'HOURLY',   0),
        (N'PM',  N'Project Management',     30, 'PM',  N'HOURLY',   0),
        (N'SUP', N'Support / Maintenance',  40, 'SUP', N'RETAINER', 0),
        (N'FIX', N'Fixed-Scope Engagement', 50, 'FIX', N'FIXED',    0),
        (N'TRN', N'Training',               60, 'TRN', N'HOURLY',   0),
        (N'SAL', N'Sales / Pre-sales',      70, 'SAL', N'NONBILL',  0),
        (N'INT', N'Internal / Admin',       80, 'INT', N'NONBILL',  0),
        (N'UNB', N'Unbillable Client Work', 90, 'UNB', N'NONBILL',  0)
    ) AS v (Code, Name, SortOrder, KeyPrefix, BillingTypeCode, IsDefault)
    JOIN lkp.DefaultBillingType AS bt ON bt.Code = v.BillingTypeCode
) AS s
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, KeyPrefix = s.KeyPrefix,
    DefaultBillingTypeId = s.DefaultBillingTypeId, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, KeyPrefix, DefaultBillingTypeId, IsDefault)
    VALUES (s.Code, s.Name, s.SortOrder, s.KeyPrefix, s.DefaultBillingTypeId, s.IsDefault);

MERGE lkp.DefaultTimeEntryStatus AS t
USING (VALUES
    (N'DRAFT',     N'Draft',       10, 'DRAFT',       1),
    (N'SUBMITTED', N'Submitted',   20, 'SUBMITTED',   0),
    (N'APPROVED',  N'Approved',    30, 'APPROVED',    0),
    (N'INVOICED',  N'Invoiced',    40, 'INVOICED',    0),
    (N'WRITEOFF',  N'Written Off', 50, 'WRITTEN_OFF', 0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault, IsLocked = 1
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault, IsLocked) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault, 1);

MERGE lkp.DefaultInvoiceStatus AS t
USING (VALUES
    (N'DRAFT',   N'Draft',          10, 'DRAFT',   1),
    (N'ISSUED',  N'Issued',         20, 'ISSUED',  0),
    (N'PARTIAL', N'Partially Paid', 30, 'PARTIAL', 0),
    (N'PAID',    N'Paid',           40, 'PAID',    0),
    (N'VOID',    N'Void',           50, 'VOID',    0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault, IsLocked = 1
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault, IsLocked) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault, 1);

MERGE lkp.DefaultInvoiceLineType AS t
USING (VALUES
    (N'TIME',     N'Time',        10, 'TIME',       1),
    (N'RETAINER', N'Retainer',    20, 'RETAINER',   0),
    (N'FIXED',    N'Fixed Fee',   30, 'FIXED_FEE',  0),
    (N'EXPENSE',  N'Expense',     40, 'EXPENSE',    0),
    (N'ADJUST',   N'Adjustment',  50, 'ADJUSTMENT', 0),
    (N'DISCOUNT', N'Discount',    60, 'DISCOUNT',   0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault, IsLocked = 1
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault, IsLocked) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault, 1);

MERGE admin.[Plan] AS t
USING (VALUES
    ('STANDARD',   N'Flat',            0.025000, NULL, NULL, 1),
    ('AI_POWERED', N'AI Powered',      0.025000, NULL, NULL, 0),
    ('AI_PLUS',    N'AI Powered Plus', 0.025000, NULL, NULL, 0),
    ('ENTERPRISE', N'Enterprise',      0.025000, NULL, NULL, 0)
) AS s (Code, Name, FeeRate, PerInvoiceCap, MonthlyMinimum, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, FeeRate = s.FeeRate, PerInvoiceCap = s.PerInvoiceCap,
    MonthlyMinimum = s.MonthlyMinimum, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, FeeRate, PerInvoiceCap, MonthlyMinimum, IsDefault)
    VALUES (s.Code, s.Name, s.FeeRate, s.PerInvoiceCap, s.MonthlyMinimum, s.IsDefault);

------------------------------------------------------------------ Reports
MERGE admin.Report AS t
USING (VALUES
    ('INVOICE_S', N'Invoice - Summary',                 'INVOICE', N'/Pillar/Invoice_Summary',    N'One line per invoice line; totals, remit-to and notes.', 10),
    ('INVOICE_T', N'Invoice - Time & materials detail', 'INVOICE', N'/Pillar/Invoice_TimeDetail', N'Grouped by project; each line lists its time entries with date, person, hours and notes.', 20),
    ('PLATFORM_STATEMENT', N'Pillar monthly statement',  'STATEMENT', N'/Pillar/PlatformStatement', N'Pillar''s monthly bill to a tenant: one line per invoice fee, minimum and credit.', 90)
) AS s (Code, Name, ReportType, ReportPath, Description, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, ReportType = s.ReportType, ReportPath = s.ReportPath, Description = s.Description, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, ReportType, ReportPath, Description, SortOrder)
    VALUES (s.Code, s.Name, s.ReportType, s.ReportPath, s.Description, s.SortOrder);

MERGE admin.ReportParameter AS t
USING (
    SELECT r.Id AS ReportId, v.Name, v.DataType, v.Source, v.SourceKey, v.SortOrder
    FROM (VALUES
        ('INVOICE_S', 'TenantId',        'INT',    'SESSION', 'TenantId', 10),
        ('INVOICE_S', 'InvoicePublicId', 'STRING', 'RECORD',  'PublicId', 20),
        ('INVOICE_T', 'TenantId',        'INT',    'SESSION', 'TenantId', 10),
        ('INVOICE_T', 'InvoicePublicId', 'STRING', 'RECORD',  'PublicId', 20),
        ('PLATFORM_STATEMENT', 'TenantId',          'INT',    'SESSION', 'TenantId', 10),
        ('PLATFORM_STATEMENT', 'StatementPublicId', 'STRING', 'RECORD',  'PublicId', 20)
    ) AS v (ReportCode, Name, DataType, Source, SourceKey, SortOrder)
    JOIN admin.Report AS r ON r.Code = v.ReportCode
) AS s
ON t.ReportId = s.ReportId AND t.Name = s.Name
WHEN MATCHED THEN UPDATE SET DataType = s.DataType, Source = s.Source, SourceKey = s.SourceKey, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (ReportId, Name, DataType, Source, SourceKey, SortOrder)
    VALUES (s.ReportId, s.Name, s.DataType, s.Source, s.SourceKey, s.SortOrder);

-- existing tenants get the Pillar layouts (no-op for tenants that have them)
EXEC ar.usp_SeedTenantInvoiceLayouts;

MERGE lkp.DefaultPaymentMethod AS t
USING (VALUES
    (N'CHECK', N'Check',       10, 1),
    (N'ACH',   N'ACH',         20, 0),
    (N'WIRE',  N'Wire',        30, 0),
    (N'CARD',  N'Credit Card', 40, 0),
    (N'CASH',  N'Cash',        50, 0),
    (N'OTHER', N'Other',       99, 0)
) AS s (Code, Name, SortOrder, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.IsDefault);

MERGE lkp.DefaultBillStatus AS t
USING (VALUES
    (N'DRAFT',     N'Draft',          10, 'DRAFT',     1),
    (N'SUBMITTED', N'Submitted',      20, 'SUBMITTED', 0),
    (N'OPEN',      N'Open',           30, 'OPEN',      0),
    (N'PARTIAL',   N'Partially Paid', 40, 'PARTIAL',   0),
    (N'PAID',      N'Paid',           50, 'PAID',      0),
    (N'VOID',      N'Void',           60, 'VOID',      0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault, IsLocked = 1
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault, IsLocked) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault, 1);

MERGE lkp.DefaultTimesheetStatus AS t
USING (VALUES
    (N'OPEN',      N'Open',      10, 'OPEN',      1),
    (N'SUBMITTED', N'Submitted', 20, 'SUBMITTED', 0),
    (N'APPROVED',  N'Approved',  30, 'APPROVED',  0),
    (N'REJECTED',  N'Rejected',  40, 'REJECTED',  0)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault, IsLocked = 1
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault, IsLocked) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault, 1);

MERGE lkp.DefaultExpenseCategory AS t
USING (VALUES
    (N'TRAVEL',   N'Travel',                 10, NULL,     NULL,   0),
    (N'LODGING',  N'Lodging',                20, NULL,     NULL,   0),
    (N'MEALS',    N'Meals',                  30, NULL,     NULL,   0),
    (N'MILEAGE',  N'Mileage',                40, N'mile',  0.7000, 0),
    (N'SOFTWARE', N'Software & Subscriptions', 50, NULL,   NULL,   0),
    (N'SUPPLIES', N'Supplies',               60, NULL,     NULL,   0),
    (N'SUBCON',   N'Subcontractor',          70, NULL,     NULL,   0),
    (N'PROF',     N'Professional Services',  80, NULL,     NULL,   0),
    (N'OTHER',    N'Other',                  99, NULL,     NULL,   1)
) AS s (Code, Name, SortOrder, UnitName, UnitRate, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, UnitName = s.UnitName, UnitRate = s.UnitRate, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, UnitName, UnitRate, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.UnitName, s.UnitRate, s.IsDefault);

------------------------------------------------------------------ Tenant types and settings
MERGE admin.TenantType AS t
USING (VALUES
    ('CONTRACTOR', N'Independent Contractor', N'One person billing their own time', 10),
    ('FIRM',       N'Small Firm',             N'A few people; owner approves time', 20),
    ('AGENCY',     N'Agency',                 N'Larger team with project managers', 30)
) AS s (Code, Name, Description, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, Description, SortOrder) VALUES (s.Code, s.Name, s.Description, s.SortOrder);

MERGE admin.SettingDefinition AS t
USING (VALUES
    -- key,                          category,    display name,                    description,                                                        type,      default, allowed,                     visibility,      user override, sort
    ('TimeEntry.RequireApproval',    N'Time',     N'Require time approval',        N'Submitted time waits for approval. Off: submitting approves it.', 'BIT',     N'1',    NULL,                        'TENANT_EDIT',   1, 10),
    ('TimeEntry.EntryMode',          N'Time',     N'Time entry method',            N'HOUR, HALF_HOUR, QUARTER_HOUR = durations in that increment; EXACT = hours:minutes; START_END = start/end times or timer.', 'STRING', N'QUARTER_HOUR', N'["HOUR","HALF_HOUR","QUARTER_HOUR","EXACT","START_END"]', 'TENANT_EDIT', 0, 15),
    ('Invoice.GenerationMode',       N'Invoicing', N'Invoice creation',             N'MANUAL = create invoice runs by hand; AUTO_DRAFT = drafts are created nightly as billing periods close. Issuing is always manual.', 'STRING', N'MANUAL', N'["MANUAL","AUTO_DRAFT"]', 'TENANT_EDIT', 0, 10),
    ('Invoice.DefaultTaxRate',       N'Invoicing', N'Default sales tax rate',       N'Decimal rate applied to taxable lines on new invoices, e.g. 0.0725. Tax-exempt profiles are never taxed.', 'DECIMAL', N'0', NULL, 'TENANT_EDIT', 0, 20),
    ('AP.RequireApproval',           N'Payables',  N'Require bill approval',        N'Submitted bills and expense reports wait for approval. Off: submitting approves them.', 'BIT', N'1', NULL, 'TENANT_EDIT', 1, 10),
    ('Feature.ExpenseReports',       N'Platform',  N'Expense reports',              N'Users can submit their own expenses for reimbursement.', 'BIT', N'0', NULL, 'PLATFORM_ONLY', 0, 30),
    ('TimeEntry.RoundingMinutes',    N'Time',     N'Round time entries up to',     N'Minutes, for EXACT and START_END entry only; 0 = no rounding.',   'INT',     N'0',    N'["0","6","15","30"]',     'TENANT_EDIT',   0, 20),
    ('Tenant.MaxUsers',              N'Account',  N'User limit',                   N'Users allowed on the plan. NULL = unlimited.',                    'INT',     NULL,    NULL,                        'TENANT_READ',   0, 10),
    ('Platform.FeeRateOverride',     N'Platform', N'Fee rate override',            N'Replaces Plan.FeeRate for this tenant, e.g. 0.02 = 2%. NULL = plan rate (2.5%).', 'DECIMAL', NULL, NULL,                 'PLATFORM_ONLY', 0, 10),
    ('Platform.FeeCapOverride',      N'Platform', N'Fee cap per invoice',          N'Replaces Plan.PerInvoiceCap for this tenant (max fee on one invoice). NULL = plan cap.', 'DECIMAL', NULL, NULL,             'PLATFORM_ONLY', 0, 12),
    ('Platform.MonthlyMinimumOverride', N'Platform', N'Monthly minimum fee',       N'Replaces Plan.MonthlyMinimum on the monthly platform statement. NULL = plan minimum.', 'DECIMAL', NULL, NULL,          'PLATFORM_ONLY', 0, 14),
    ('Feature.CustomInvoiceLayouts', N'Platform', N'Custom invoice layouts',       N'Paid custom development: tenant may use custom RDL layouts.',     'BIT',     N'0',    NULL,                        'PLATFORM_ONLY', 0, 20),
    ('Feature.Pilo',                 N'Platform', N'Pilo',                         N'All Pilo AI features (Ask Pilo, Polish with Pilo). On for the AI plans.', 'BIT', N'0', NULL,                     'PLATFORM_ONLY', 0, 40),
    ('Feature.ExtendedBranding',     N'Platform', N'Extended branding',            N'In-app logo and accent theme. On for AI Powered Plus and Enterprise.', 'BIT', N'0', NULL,                       'PLATFORM_ONLY', 0, 50),
    ('TimeEntry.NoteRequired',       N'Time',     N'Require a description',        N'Every time entry needs a description before it is saved or submitted.', 'BIT', N'1', NULL,                     'TENANT_EDIT',   0, 25),
    ('Timesheet.LockOnSubmit',       N'Time',     N'Lock submitted weeks',         N'A submitted week is read-only for the person who entered it until it is sent back.', 'BIT', N'1', NULL,        'TENANT_EDIT',   0, 30),
    ('Timesheet.AllowResubmit',      N'Time',     N'Allow adding to submitted weeks', N'People may add time to a submitted (not yet approved) week and submit again.', 'BIT', N'1', NULL,          'TENANT_EDIT',   0, 35),
    ('Timesheet.WeekStartDay',       N'Time',     N'Week starts on',               N'First day of a timesheet week: 1 = Monday ... 7 = Sunday. Applies to weeks created after a change.', 'INT', N'1', N'["1","2","3","4","5","6","7"]', 'TENANT_EDIT', 0, 40),
    ('Dashboard.MembersSeeMoney',    N'Dashboard', N'Members see money',           N'Members see amounts and money widgets on Today. Off: hours only.', 'BIT', N'0', NULL,                        'TENANT_EDIT',   0, 10)
) AS s (SettingKey, Category, DisplayName, Description, DataType, DefaultValue, AllowedValues, Visibility, AllowUserOverride, SortOrder)
ON t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Category = s.Category, DisplayName = s.DisplayName, Description = s.Description, DataType = s.DataType,
    DefaultValue = s.DefaultValue, AllowedValues = s.AllowedValues, Visibility = s.Visibility,
    AllowUserOverride = s.AllowUserOverride, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (SettingKey, Category, DisplayName, Description, DataType, DefaultValue, AllowedValues, Visibility, AllowUserOverride, SortOrder)
    VALUES (s.SettingKey, s.Category, s.DisplayName, s.Description, s.DataType, s.DefaultValue, s.AllowedValues, s.Visibility, s.AllowUserOverride, s.SortOrder);

MERGE admin.TenantTypeSettingDefault AS t
USING (
    SELECT tt.Id AS TenantTypeId, v.SettingKey, v.Value
    FROM (VALUES
        ('CONTRACTOR', 'TimeEntry.RequireApproval', N'0'),
        ('CONTRACTOR', 'AP.RequireApproval',        N'0')
    ) AS v (TenantTypeCode, SettingKey, Value)
    JOIN admin.TenantType AS tt ON tt.Code = v.TenantTypeCode
) AS s
ON t.TenantTypeId = s.TenantTypeId AND t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Value = s.Value
WHEN NOT MATCHED THEN INSERT (TenantTypeId, SettingKey, Value) VALUES (s.TenantTypeId, s.SettingKey, s.Value);

MERGE admin.PlanSettingDefault AS t
USING (
    SELECT p.Id AS PlanId, v.SettingKey, v.Value
    FROM (VALUES
        ('AI_POWERED', 'Feature.Pilo',             N'1'),
        ('AI_PLUS',    'Feature.Pilo',             N'1'),
        ('AI_PLUS',    'Feature.ExtendedBranding', N'1'),
        ('ENTERPRISE', 'Feature.Pilo',             N'1'),
        ('ENTERPRISE', 'Feature.ExtendedBranding', N'1')
    ) AS v (PlanCode, SettingKey, Value)
    JOIN admin.[Plan] AS p ON p.Code = v.PlanCode
) AS s
ON t.PlanId = s.PlanId AND t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Value = s.Value
WHEN NOT MATCHED THEN INSERT (PlanId, SettingKey, Value) VALUES (s.PlanId, s.SettingKey, s.Value);

------------------------------------------------------------------ Users and roles
MERGE sec.Permission AS t
USING (VALUES
    ('client.view', N'Clients', N'View clients and contacts', 10),
    ('client.edit', N'Clients', N'Add and edit clients, contacts and billing profiles', 20),
    ('project.view', N'Projects', N'View projects and tasks', 30),
    ('project.edit', N'Projects', N'Add and edit projects', 40),
    ('project.members', N'Projects', N'Assign people to projects', 50),
    ('project.rates', N'Projects', N'Set project and person rates', 60),
    ('task.edit', N'Projects', N'Add and edit tasks, comments and attachments', 70),
    ('time.enter', N'Time', N'Enter and submit own time', 80),
    ('time.enter_others', N'Time', N'Enter and submit time for other people', 90),
    ('time.view_all', N'Time', N'See everyone''s time', 100),
    ('time.approve', N'Time', N'Approve and reject time', 110),
    ('invoice.view', N'Invoicing', N'View invoices', 120),
    ('invoice.run', N'Invoicing', N'Run invoice batches and edit drafts', 130),
    ('invoice.issue', N'Invoicing', N'Issue invoices', 140),
    ('invoice.void', N'Invoicing', N'Void issued invoices', 150),
    ('payment.record', N'Receivables', N'Record and apply client payments', 160),
    ('payment.void', N'Receivables', N'Void payments, issue credit memos and refunds', 170),
    ('ap.view', N'Payables', N'View vendors and bills', 180),
    ('ap.enter', N'Payables', N'Add vendors and enter bills', 190),
    ('ap.approve', N'Payables', N'Approve bills and expense reports', 200),
    ('ap.pay', N'Payables', N'Record bill payments', 210),
    ('expense.submit', N'Payables', N'Submit own expense reports', 220),
    ('report.financial', N'Reports', N'See financial reports (AR, AP, revenue, margin)', 230),
    ('settings.edit', N'Administration', N'Change account settings, branding, layouts and remit-to', 240),
    ('users.manage', N'Administration', N'Invite, edit and disable users', 250),
    ('billing.manage', N'Administration', N'Manage the Pillar subscription, card on file and statements', 260)
) AS s (Code, Category, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Category = s.Category, Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Category, Name, SortOrder) VALUES (s.Code, s.Category, s.Name, s.SortOrder);

MERGE sec.DefaultRole AS t
USING (VALUES
    ('OWNER', N'Owner', N'Everything, including the Pillar subscription. At least one active owner is required.', 1, 0, 10),
    ('ADMIN', N'Admin', N'Everything except the Pillar subscription.', 0, 0, 20),
    ('MANAGER', N'Manager', N'Runs projects: assigns people, enters and approves time.', 0, 0, 30),
    ('BILLING', N'Billing', N'Invoicing, receivables and payables.', 0, 0, 40),
    ('MEMBER', N'Member', N'Logs own time and expenses on assigned projects.', 0, 1, 50)
) AS s (Code, Name, Description, IsOwner, IsDefault, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description, IsOwner = s.IsOwner, IsDefault = s.IsDefault, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, Description, IsOwner, IsDefault, SortOrder)
    VALUES (s.Code, s.Name, s.Description, s.IsOwner, s.IsDefault, s.SortOrder);

-- additive: a permission dropped here stays on tenant roles until removed by hand
MERGE sec.DefaultRolePermission AS t
USING (VALUES
    ('ADMIN', 'client.view'),
    ('ADMIN', 'client.edit'),
    ('ADMIN', 'project.view'),
    ('ADMIN', 'project.edit'),
    ('ADMIN', 'project.members'),
    ('ADMIN', 'project.rates'),
    ('ADMIN', 'task.edit'),
    ('ADMIN', 'time.enter'),
    ('ADMIN', 'time.enter_others'),
    ('ADMIN', 'time.view_all'),
    ('ADMIN', 'time.approve'),
    ('ADMIN', 'invoice.view'),
    ('ADMIN', 'invoice.run'),
    ('ADMIN', 'invoice.issue'),
    ('ADMIN', 'invoice.void'),
    ('ADMIN', 'payment.record'),
    ('ADMIN', 'payment.void'),
    ('ADMIN', 'ap.view'),
    ('ADMIN', 'ap.enter'),
    ('ADMIN', 'ap.approve'),
    ('ADMIN', 'ap.pay'),
    ('ADMIN', 'expense.submit'),
    ('ADMIN', 'report.financial'),
    ('ADMIN', 'settings.edit'),
    ('ADMIN', 'users.manage'),
    ('MANAGER', 'client.view'),
    ('MANAGER', 'project.view'),
    ('MANAGER', 'project.edit'),
    ('MANAGER', 'project.members'),
    ('MANAGER', 'task.edit'),
    ('MANAGER', 'time.enter'),
    ('MANAGER', 'time.enter_others'),
    ('MANAGER', 'time.view_all'),
    ('MANAGER', 'time.approve'),
    ('MANAGER', 'invoice.view'),
    ('MANAGER', 'expense.submit'),
    ('BILLING', 'client.view'),
    ('BILLING', 'client.edit'),
    ('BILLING', 'project.view'),
    ('BILLING', 'project.rates'),
    ('BILLING', 'time.view_all'),
    ('BILLING', 'invoice.view'),
    ('BILLING', 'invoice.run'),
    ('BILLING', 'invoice.issue'),
    ('BILLING', 'invoice.void'),
    ('BILLING', 'payment.record'),
    ('BILLING', 'payment.void'),
    ('BILLING', 'ap.view'),
    ('BILLING', 'ap.enter'),
    ('BILLING', 'ap.approve'),
    ('BILLING', 'ap.pay'),
    ('BILLING', 'expense.submit'),
    ('BILLING', 'report.financial'),
    ('BILLING', 'time.enter'),
    ('MEMBER', 'client.view'),
    ('MEMBER', 'project.view'),
    ('MEMBER', 'task.edit'),
    ('MEMBER', 'time.enter'),
    ('MEMBER', 'expense.submit')
) AS s (RoleCode, PermissionCode)
ON t.RoleCode = s.RoleCode AND t.PermissionCode = s.PermissionCode
WHEN NOT MATCHED BY TARGET THEN INSERT (RoleCode, PermissionCode) VALUES (s.RoleCode, s.PermissionCode)
WHEN NOT MATCHED BY SOURCE THEN DELETE;

-- existing tenants get missing roles and newly granted permissions
EXEC sec.usp_SeedTenantRoles;

EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
