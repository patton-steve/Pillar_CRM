/*
Post-deployment seed: Pillar-owned rows (SystemCode and lkp.Default* masters).
Runs after every publish and is rerunnable. It inserts missing rows and updates
Pillar-owned columns. It never deletes or changes tenant rows; near the end it runs
lkp.usp_SyncTenantLookups, which only adds missing default lookup rows to each tenant.
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
    ('TimesheetStatus',  'REJECTED',    N'Time sent back with a reason', 40),
    ('NoteType',         'CALL',        N'Phone or video call', 10),
    ('NoteType',         'MEETING',     N'Meeting', 20),
    ('NoteType',         'EMAIL',       N'Email', 30),
    ('NoteType',         'NOTE',        N'General note', 40)
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

-- Prices and seats (Steve 2026-10-22). Extra seats are $12 per user per month on every plan, Flat included.
MERGE admin.[Plan] AS t
USING (VALUES
    --                                 fee rate   cap   min   default  price  seats  extra seat  AI reports  overage  sort
    ('STANDARD',   N'Flat',            0.025000, NULL, NULL, 1,        0.00,  2,     12.00,      0,          NULL,    10),
    ('AI_POWERED', N'AI Powered',      0.025000, NULL, NULL, 0,       39.00,  5,     12.00,      60,         0.75,    20),
    ('AI_PLUS',    N'AI Powered Plus', 0.025000, NULL, NULL, 0,       89.00,  10,    12.00,      200,        0.50,    30),
    ('ENTERPRISE', N'Enterprise',      0.025000, NULL, NULL, 0,      209.00,  20,    12.00,      500,        0.35,    40)
) AS s (Code, Name, FeeRate, PerInvoiceCap, MonthlyMinimum, IsDefault, MonthlyPrice, IncludedSeats, ExtraSeatPrice, IncludedAiReports, AiOveragePrice, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, FeeRate = s.FeeRate, PerInvoiceCap = s.PerInvoiceCap,
    MonthlyMinimum = s.MonthlyMinimum, IsDefault = s.IsDefault, MonthlyPrice = s.MonthlyPrice, IncludedSeats = s.IncludedSeats,
    ExtraSeatPrice = s.ExtraSeatPrice, IncludedAiReports = s.IncludedAiReports, AiOveragePrice = s.AiOveragePrice, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, FeeRate, PerInvoiceCap, MonthlyMinimum, IsDefault, MonthlyPrice, IncludedSeats, ExtraSeatPrice,
    IncludedAiReports, AiOveragePrice, SortOrder)
    VALUES (s.Code, s.Name, s.FeeRate, s.PerInvoiceCap, s.MonthlyMinimum, s.IsDefault, s.MonthlyPrice, s.IncludedSeats, s.ExtraSeatPrice,
    s.IncludedAiReports, s.AiOveragePrice, s.SortOrder);

------------------------------------------------------------------ Reports
MERGE admin.ReportCategory AS t
USING (VALUES
    ('MONEY',    N'Money',           10),
    ('TIME',     N'Time',            20),
    ('PROJECTS', N'Projects',        30),
    ('CLIENTS',  N'Clients',         40),
    ('BILLS',    N'Bills & vendors', 50)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

MERGE admin.ReportRenderType AS t
USING (VALUES
    ('TABLE',       N'Table',                 10),
    ('BAR',         N'Bar',                   20),
    ('STACKED_BAR', N'Stacked bar',           30),
    ('LINE',        N'Line',                  40),
    ('AREA',        N'Area',                  50),
    ('DONUT',       N'Donut',                 60),
    ('KPI',         N'KPI cards',             70),
    ('PIVOT',       N'Pivot / matrix',        80),
    ('TREND',       N'Trend vs last period',  90),
    ('AGING',       N'Aging buckets',        100),
    ('WATERFALL',   N'Waterfall',            110),
    ('SCATTER',     N'Scatter',              120),
    ('HEATMAP',     N'Calendar heatmap',     130)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

-- canned (ANALYTIC) reports: add a row with CategoryCode and PermissionCode once its RDL is deployed, and its
-- USER parameters below with Label, ListSource and IsRequired
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

MERGE lkp.DefaultNoteType AS t
USING (VALUES
    (N'CALL',    N'Call',    10, 'CALL',    0),
    (N'MEETING', N'Meeting', 20, 'MEETING', 0),
    (N'EMAIL',   N'Email',   30, 'EMAIL',   0),
    (N'NOTE',    N'Note',    40, 'NOTE',    1)
) AS s (Code, Name, SortOrder, SystemCode, IsDefault)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder, SystemCode = s.SystemCode, IsDefault = s.IsDefault
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder, SystemCode, IsDefault) VALUES (s.Code, s.Name, s.SortOrder, s.SystemCode, s.IsDefault);

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

------------------------------------------------------------------ Project setup checks
MERGE admin.ProjectSetupCheck AS t
USING (VALUES
    ('TEAM',                   N'Team',                   N'At least one person is on the project team.', N'Add at least one person to the project team.', 'ALL', 'BLOCK', 10),
    ('RATE',                   N'Rate',                   N'Hourly and not-to-exceed projects have a default rate or a project rate.', N'Set a default rate or add a project rate.', 'HOURLY,NTE', 'BLOCK', 20),
    ('BUDGET',                 N'Budget',                 N'Hourly projects have budget hours or a budget amount.', N'Set budget hours or a budget amount.', 'HOURLY', 'BLOCK', 30),
    ('FEE',                    N'Fee',                    N'Fixed-fee and retainer projects have their fee.', N'Set the project fee.', 'FIXED,RETAINER', 'BLOCK', 40),
    ('MILESTONES',             N'Billing schedule',       N'Fixed-fee projects have a billing schedule that adds up to the fee. Blocking means DATE or MANUAL milestones come first; TASK milestones can be added once tasks exist.', N'Add a billing schedule so the fee can be invoiced.', 'FIXED', 'WARN', 50),
    ('PROJECT_MANAGER',        N'Project manager',        N'A project manager is assigned.', N'Assign a project manager.', 'ALL', 'OFF', 60),
    ('START_DATE',             N'Start date',             N'The project has a start date.', N'Set a start date.', 'ALL', 'OFF', 70),
    ('END_DATE',               N'End date',               N'The project has an end date.', N'Set an end date.', 'ALL', 'OFF', 80),
    ('PO_NUMBER',              N'PO number',              N'The project has the client''s PO number.', N'Enter the PO number.', 'ALL', 'OFF', 90),
    ('BILLING_CONTACT',        N'Billing contact',        N'The project''s billing profile has a billing contact.', N'Add a billing contact to the billing profile.', 'HOURLY,NTE,FIXED,RETAINER', 'OFF', 100),
    ('REQUIRED_CUSTOM_FIELDS', N'Required custom fields', N'Every required project custom field is filled in.', N'Fill in the required custom fields.', 'ALL', 'OFF', 110)
) AS s (Code, Name, Description, Message, AppliesTo, DefaultLevel, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description, Message = s.Message, AppliesTo = s.AppliesTo,
    DefaultLevel = s.DefaultLevel, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, Description, Message, AppliesTo, DefaultLevel, SortOrder)
    VALUES (s.Code, s.Name, s.Description, s.Message, s.AppliesTo, s.DefaultLevel, s.SortOrder);

-- Project.RequireBudget (handoff 16) became the BUDGET check: carry a tenant's "off" over, then retire the setting
IF EXISTS (SELECT 1 FROM admin.SettingDefinition WHERE SettingKey = 'Project.RequireBudget')
BEGIN
    INSERT INTO admin.TenantProjectSetupCheck (TenantId, CheckCode, Level)
    SELECT s.TenantId, 'BUDGET', 'OFF' FROM admin.TenantSetting AS s
    WHERE s.SettingKey = 'Project.RequireBudget' AND s.Value = N'0'
      AND NOT EXISTS (SELECT 1 FROM admin.TenantProjectSetupCheck AS x WHERE x.TenantId = s.TenantId AND x.CheckCode = 'BUDGET');
    DELETE FROM admin.UserSetting WHERE SettingKey = 'Project.RequireBudget';
    DELETE FROM admin.TenantSetting WHERE SettingKey = 'Project.RequireBudget';
    DELETE FROM admin.TenantTypeSettingDefault WHERE SettingKey = 'Project.RequireBudget';
    DELETE FROM admin.PlanSettingDefault WHERE SettingKey = 'Project.RequireBudget';
    DELETE FROM admin.SettingDefinition WHERE SettingKey = 'Project.RequireBudget';
END;

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
    ('Tenant.MaxUsers',              N'Account',  N'User limit',                   N'Hard cap on logins that Pillar sets for a tenant. NULL = none: logins past the plan''s included seats are billed as extra seats.', 'INT', NULL, NULL, 'TENANT_READ', 0, 10),
    ('Platform.FeeRateOverride',     N'Platform', N'Fee rate override',            N'Replaces Plan.FeeRate for this tenant, e.g. 0.02 = 2%. NULL = plan rate (2.5%).', 'DECIMAL', NULL, NULL,                 'PLATFORM_ONLY', 0, 10),
    ('Platform.FeeCapOverride',      N'Platform', N'Fee cap per invoice',          N'Replaces Plan.PerInvoiceCap for this tenant (max fee on one invoice). NULL = plan cap.', 'DECIMAL', NULL, NULL,             'PLATFORM_ONLY', 0, 12),
    ('Platform.MonthlyMinimumOverride', N'Platform', N'Monthly minimum fee',       N'Replaces Plan.MonthlyMinimum on the monthly platform statement. NULL = plan minimum.', 'DECIMAL', NULL, NULL,          'PLATFORM_ONLY', 0, 14),
    ('Feature.CustomInvoiceLayouts', N'Platform', N'Custom invoice layouts',       N'Paid custom development: tenant may use custom RDL layouts.',     'BIT',     N'0',    NULL,                        'PLATFORM_ONLY', 0, 20),
    ('Feature.Pilo',                 N'Platform', N'Pilo',                         N'All Pilo AI features (Ask Pilo, Polish with Pilo). On for the AI plans.', 'BIT', N'0', NULL,                     'PLATFORM_ONLY', 0, 40),
    ('Feature.ExtendedBranding',     N'Platform', N'Extended branding',            N'In-app logo, colors and sign-in page branding. Enterprise only.', 'BIT', N'0', NULL,                       'PLATFORM_ONLY', 0, 50),
    ('TimeEntry.NoteRequired',       N'Time',     N'Require a description',        N'Every time entry needs a description before it is saved or submitted.', 'BIT', N'1', NULL,                     'TENANT_EDIT',   0, 25),
    ('Timesheet.LockOnSubmit',       N'Time',     N'Lock submitted weeks',         N'A submitted week is read-only for the person who entered it until it is sent back.', 'BIT', N'1', NULL,        'TENANT_EDIT',   0, 30),
    ('Timesheet.AllowResubmit',      N'Time',     N'Allow adding to submitted weeks', N'People may add time to a submitted (not yet approved) week and submit again.', 'BIT', N'1', NULL,          'TENANT_EDIT',   0, 35),
    ('Timesheet.WeekStartDay',       N'Time',     N'Week starts on',               N'First day of a timesheet week: 1 = Monday ... 7 = Sunday. Applies to weeks created after a change.', 'INT', N'1', N'["1","2","3","4","5","6","7"]', 'TENANT_EDIT', 0, 40),
    ('Dashboard.MembersSeeMoney',    N'Dashboard', N'Members see money',           N'Members see amounts and money widgets on Today. Off: hours only.', 'BIT', N'0', NULL,                        'TENANT_EDIT',   0, 10),
    ('Project.BudgetAlertPercents',  N'Projects', N'Budget alerts at',             N'Comma-separated percents of budget that notify the project manager, e.g. 80,100. A project can override it.', 'STRING', N'80,100', NULL, 'TENANT_EDIT', 0, 20),
    ('Pilo.SavedReportsPerUser',     N'Platform', N'Saved AI reports per person',  N'How many Pilo reports each person can save. Plan-derived: 5 / 10 / 25.', 'INT', N'0', NULL,                'PLATFORM_ONLY', 0, 42),
    ('Pilo.CompanyReports',          N'Platform', N'Company AI reports',           N'How many Pilo reports the company can share. Plan-derived: 50 on Enterprise, 0 below.', 'INT', N'0', NULL,   'PLATFORM_ONLY', 0, 44),
    ('Pilo.WritingStyle',            N'Pilo',     N'Pilo writing style',           N'How Polish with Pilo rewrites notes. A person can pick their own.', 'STRING', N'PLAIN', N'["PLAIN","FRIENDLY","FORMAL","CONCISE"]', 'TENANT_EDIT', 1, 10),
    ('Security.RequireMfa',          N'Security', N'Require two-step sign-in',     N'Everyone must set up an authenticator app; sign-in asks them to enroll first.', 'BIT', N'0', NULL, 'TENANT_EDIT', 0, 10),
    ('Security.PasswordMinLength',   N'Security', N'Minimum password length',      N'Characters a new password needs.', 'INT', N'10', N'["8","10","12","14","16"]', 'TENANT_EDIT', 0, 20),
    ('Security.PasswordRequireMixed',N'Security', N'Require mixed characters',     N'New passwords need upper and lower case letters and a number or symbol.', 'BIT', N'0', NULL, 'TENANT_EDIT', 0, 30),
    ('Security.SessionTimeoutMinutes', N'Security', N'Sign out after idle',        N'Minutes without activity before sign-in is needed again; 0 = never.', 'INT', N'480', N'["0","15","30","60","240","480","1440"]', 'TENANT_EDIT', 0, 40),
    ('Security.MaxSessionDays',      N'Security', N'Longest session',              N'Days a sign-in lasts at most, even when active.', 'INT', N'30', N'["1","7","14","30","90"]', 'TENANT_EDIT', 0, 50),
    ('Billing.StatementEmail',       N'Billing',  N'Send Pillar statements to',    N'Email address for the monthly Pillar statement. Empty = the account owners.', 'STRING', NULL, NULL, 'TENANT_EDIT', 0, 10),
    ('Pilo.OverageCapAmount',        N'Billing',  N'Pilo overage cap',             N'Most the company pays a month for Pilo reports past the plan''s allowance; Pilo reports stop at the cap. Empty = no cap.', 'DECIMAL', NULL, NULL, 'TENANT_EDIT', 0, 20),
    ('Seats.IncludedOverride',       N'Platform', N'Included seats',               N'Replaces Plan.IncludedSeats for this tenant (custom quote). NULL = plan seats.', 'INT', NULL, NULL, 'PLATFORM_ONLY', 0, 60),
    ('Seats.ExtraPriceOverride',     N'Platform', N'Extra seat price',             N'Replaces Plan.ExtraSeatPrice for this tenant (custom quote). NULL = plan price.', 'DECIMAL', NULL, NULL, 'PLATFORM_ONLY', 0, 62),
    ('Pilo.MonthlyReportsOverride',  N'Platform', N'Pilo reports a month',         N'Replaces Plan.IncludedAiReports for this tenant. NULL = plan allowance.', 'INT', NULL, NULL, 'PLATFORM_ONLY', 0, 64),
    ('Time.WeeklyHoursGoal',         N'Time',     N'Weekly hours goal',            N'Hours a person aims to log each week, shown on Today. A person can have their own goal.', 'DECIMAL', N'40', NULL, 'TENANT_EDIT', 1, 50),
    ('Pilo.ReceiptsCountTowardQuota', N'Platform', N'Receipt reads count as Pilo reports', N'On: each Pilo receipt read counts toward the monthly Pilo report allowance. Off (default): fair use, like Polish with Pilo.', 'BIT', N'0', NULL, 'PLATFORM_ONLY', 0, 66)
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

-- Extended branding is Enterprise only (Steve 2026-10-21)
DELETE d FROM admin.PlanSettingDefault AS d JOIN admin.[Plan] AS p ON p.Id = d.PlanId
WHERE p.Code = 'AI_PLUS' AND d.SettingKey = 'Feature.ExtendedBranding';

MERGE admin.PlanSettingDefault AS t
USING (
    SELECT p.Id AS PlanId, v.SettingKey, v.Value
    FROM (VALUES
        ('AI_POWERED', 'Feature.Pilo',             N'1'),
        ('AI_PLUS',    'Feature.Pilo',             N'1'),
        ('ENTERPRISE', 'Feature.Pilo',             N'1'),
        ('ENTERPRISE', 'Feature.ExtendedBranding', N'1'),
        ('AI_POWERED', 'Pilo.SavedReportsPerUser', N'5'),
        ('AI_PLUS',    'Pilo.SavedReportsPerUser', N'10'),
        ('ENTERPRISE', 'Pilo.SavedReportsPerUser', N'25'),
        ('ENTERPRISE', 'Pilo.CompanyReports',      N'50')
    ) AS v (PlanCode, SettingKey, Value)
    JOIN admin.[Plan] AS p ON p.Code = v.PlanCode
) AS s
ON t.PlanId = s.PlanId AND t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Value = s.Value
WHEN NOT MATCHED THEN INSERT (PlanId, SettingKey, Value) VALUES (s.PlanId, s.SettingKey, s.Value);

------------------------------------------------------------------ Users and roles
-- grid headers; add a row here and it appears in Settings > Roles
MERGE sec.PermissionCategory AS t
USING (VALUES
    ('CLIENTS',        N'Clients',            N'Clients, contacts and billing profiles.', 10),
    ('PROJECTS',       N'Projects',           N'Projects, team and rates.', 20),
    ('TASKS',          N'Tasks',              N'Tasks, comments, checklists and attachments.', 30),
    ('TIME',           N'Time',               N'Time entry, timesheets and approval.', 40),
    ('EXPENSES',       N'Expenses',           N'Expense reports people submit for reimbursement.', 50),
    ('INVOICING',      N'Invoicing',          N'Invoice runs, drafts, issuing and voids.', 60),
    ('PAYMENTS',       N'Payments',           N'Client payments, credit memos and refunds.', 70),
    ('BILLS',          N'Bills & vendors',    N'Vendors, bills, approval and bill payments.', 80),
    ('REPORTS',        N'Reports & Pilo',     N'Canned reports and Pilo AI reports.', 90),
    ('SETTINGS',       N'Settings',           N'Account settings, branding, email and layouts.', 100),
    ('USERS',          N'Users & security',   N'People, roles and permissions.', 110),
    ('PILLAR_BILLING', N'Pillar billing',     N'The Pillar subscription, card on file and statements.', 120)
) AS s (Code, Name, Description, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, Description, SortOrder) VALUES (s.Code, s.Name, s.Description, s.SortOrder);

-- The permission catalog. To retire one, set IsActive = 0 here (keep the row: grants stay but stop counting).
-- New rows reach system roles through sec.DefaultRolePermission; roles a tenant customized get them OFF.
MERGE sec.Permission AS t
USING (
    SELECT v.Code, v.CategoryCode, c.Name AS Category, v.Name, v.Description, v.SortOrder, v.IsActive
    FROM (VALUES
    ('client.view',       'CLIENTS',        N'View clients',            N'See clients, contacts, notes and billing profiles.', 10, 1),
    ('client.edit',       'CLIENTS',        N'Edit clients',            N'Add and edit clients, contacts and billing profiles.', 20, 1),
    ('project.view',      'PROJECTS',       N'View projects',           N'See projects and their tasks.', 30, 1),
    ('project.edit',      'PROJECTS',       N'Edit projects',           N'Add and edit projects, budgets and milestones.', 40, 1),
    ('project.members',   'PROJECTS',       N'Assign people',           N'Add and remove people on a project.', 50, 1),
    ('project.rates',     'PROJECTS',       N'Set rates',               N'Set project and per-person billing rates.', 60, 1),
    ('task.create',       'TASKS',          N'Create tasks',            N'Add tasks to projects.', 70, 1),
    ('task.edit',         'TASKS',          N'Edit tasks',              N'Edit tasks, checklists, comments and attachments.', 75, 1),
    ('time.enter',        'TIME',           N'Enter own time',          N'Log and submit your own time.', 80, 1),
    ('time.enter_others', 'TIME',           N'Enter time for others',   N'Log and submit time on behalf of other people.', 90, 1),
    ('time.view_all',     'TIME',           N'See everyone''s time',    N'See time and timesheets for everyone, not just your own.', 100, 1),
    ('time.approve',      'TIME',           N'Approve time',            N'Approve, send back and correct timesheets.', 110, 1),
    ('expense.submit',    'EXPENSES',       N'Submit expenses',         N'Submit your own expense reports for reimbursement.', 115, 1),
    ('invoice.view',      'INVOICING',      N'View invoices',           N'See draft and issued invoices.', 120, 1),
    ('invoice.run',       'INVOICING',      N'Run invoices',            N'Run invoice batches and edit drafts.', 130, 1),
    ('invoice.issue',     'INVOICING',      N'Issue invoices',          N'Issue invoices (assigns the number) and email them.', 140, 1),
    ('invoice.void',      'INVOICING',      N'Void invoices',           N'Void issued invoices that have no payments.', 150, 1),
    ('payment.record',    'PAYMENTS',       N'Record payments',         N'Record client payments and apply them to invoices.', 160, 1),
    ('payment.void',      'PAYMENTS',       N'Void payments and refund', N'Void payments, issue credit memos and refunds.', 170, 1),
    ('ap.view',           'BILLS',          N'View bills',              N'See vendors and bills.', 180, 1),
    ('ap.enter',          'BILLS',          N'Enter bills',             N'Add vendors and enter bills.', 190, 1),
    ('ap.approve',        'BILLS',          N'Approve bills',           N'Approve bills and expense reports.', 200, 1),
    ('ap.pay',            'BILLS',          N'Pay bills',               N'Record bill payments.', 210, 1),
    ('report.financial',  'REPORTS',        N'Financial reports',       N'See AR, AP, revenue and margin reports.', 230, 1),
    ('report.share',      'REPORTS',        N'Share Pilo reports',      N'Save Pilo reports for the whole company and manage them.', 235, 1),
    ('settings.edit',     'SETTINGS',       N'Change settings (retired)', N'Replaced by one permission per settings page in handoff 21.', 240, 0),
    ('settings.company',  'SETTINGS',       N'Company',                 N'Company details, time zone, remit-to and dashboard options.', 241, 1),
    ('settings.lists',    'SETTINGS',       N'Lists',                   N'Edit lookup lists: client types, task types, expense categories and the rest.', 242, 1),
    ('settings.time',     'SETTINGS',       N'Time',                    N'Time entry method, rounding, approval and timesheet rules.', 243, 1),
    ('settings.projects', 'SETTINGS',       N'Projects',                N'Project setup checks, budget alerts and project defaults.', 244, 1),
    ('settings.invoicing','SETTINGS',       N'Invoicing',               N'Invoice creation, tax, layouts and bill approval rules.', 245, 1),
    ('settings.email',    'SETTINGS',       N'Email',                   N'Outgoing mail server and email templates.', 246, 1),
    ('settings.branding', 'SETTINGS',       N'Branding',                N'Logo, colors and sign-in page branding.', 247, 1),
    ('settings.integrations','SETTINGS',    N'Integrations',            N'Connect other apps.', 248, 1),
    ('settings.pilo',     'SETTINGS',       N'Pilo',                    N'Pilo AI options for the company.', 249, 1),
    ('settings.security', 'SETTINGS',       N'Security',                N'Require MFA, password rules and session timeouts.', 250, 1),
    ('settings.custom_fields','SETTINGS',   N'Custom fields',           N'Add and arrange custom fields on records.', 251, 1),
    ('settings.notifications','SETTINGS',   N'Notification defaults',   N'Company defaults for notifications, and which ones people can''t turn off.', 252, 1),
    ('settings.audit',    'SETTINGS',       N'Audit log',               N'View the log of every admin change.', 253, 1),
    ('users.manage',      'USERS',          N'Manage users and roles',  N'Invite, edit and disable people; edit roles and permissions.', 250, 1),
    ('billing.manage',    'PILLAR_BILLING', N'Manage Pillar billing',   N'Manage the Pillar subscription, card on file and statements.', 260, 1)
    ) AS v (Code, CategoryCode, Name, Description, SortOrder, IsActive)
    JOIN sec.PermissionCategory AS c ON c.Code = v.CategoryCode
) AS s
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET CategoryCode = s.CategoryCode, Category = s.Category, Name = s.Name, Description = s.Description,
    SortOrder = s.SortOrder, IsActive = s.IsActive
WHEN NOT MATCHED THEN INSERT (Code, CategoryCode, Category, Name, Description, SortOrder, IsActive)
    VALUES (s.Code, s.CategoryCode, s.Category, s.Name, s.Description, s.SortOrder, s.IsActive);

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
    ('ADMIN', 'task.create'),
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
    ('ADMIN', 'report.share'),
    ('ADMIN', 'settings.company'),
    ('ADMIN', 'settings.lists'),
    ('ADMIN', 'settings.time'),
    ('ADMIN', 'settings.projects'),
    ('ADMIN', 'settings.invoicing'),
    ('ADMIN', 'settings.email'),
    ('ADMIN', 'settings.branding'),
    ('ADMIN', 'settings.integrations'),
    ('ADMIN', 'settings.pilo'),
    ('ADMIN', 'settings.security'),
    ('ADMIN', 'settings.custom_fields'),
    ('ADMIN', 'settings.notifications'),
    ('ADMIN', 'settings.audit'),
    ('ADMIN', 'users.manage'),
    ('MANAGER', 'client.view'),
    ('MANAGER', 'project.view'),
    ('MANAGER', 'project.edit'),
    ('MANAGER', 'project.members'),
    ('MANAGER', 'task.create'),
    ('MANAGER', 'task.edit'),
    ('MANAGER', 'time.enter'),
    ('MANAGER', 'time.enter_others'),
    ('MANAGER', 'time.view_all'),
    ('MANAGER', 'time.approve'),
    ('MANAGER', 'report.share'),
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

-- handoff 21, one time: whoever held settings.edit gets every per-page settings permission, then the old grant goes.
-- Runs only while settings.edit grants remain, so later changes to the new permissions are never undone.
INSERT INTO sec.RolePermission (TenantId, RoleId, PermissionCode)
SELECT rp.TenantId, rp.RoleId, p.Code
FROM sec.RolePermission AS rp
JOIN sec.Permission AS p ON p.Code LIKE 'settings.%' AND p.Code <> 'settings.edit' AND p.IsActive = 1
WHERE rp.PermissionCode = 'settings.edit'
  AND NOT EXISTS (SELECT 1 FROM sec.RolePermission AS x WHERE x.TenantId = rp.TenantId AND x.RoleId = rp.RoleId AND x.PermissionCode = p.Code);
DELETE FROM sec.RolePermission WHERE PermissionCode = 'settings.edit';

-- which settings page guards each setting (admin.usp_Setting_Set); Platform settings stay Pillar-only
UPDATE d SET PermissionCode = m.PermissionCode
FROM admin.SettingDefinition AS d
LEFT JOIN (VALUES
    (N'Time', 'settings.time'), (N'Projects', 'settings.projects'), (N'Invoicing', 'settings.invoicing'),
    (N'Payables', 'settings.invoicing'), (N'Account', 'settings.company'), (N'Dashboard', 'settings.company'),
    (N'Pilo', 'settings.pilo'), (N'Security', 'settings.security'), (N'Billing', 'billing.manage')
) AS m (Category, PermissionCode) ON m.Category = d.Category
WHERE EXISTS (SELECT d.PermissionCode EXCEPT SELECT m.PermissionCode);

------------------------------------------------------------------ Notification types
MERGE sec.NotificationType AS t
USING (VALUES
    -- code,                         name,                            description,                                                   category,  in-app, email, sort, quick action
    ('BUDGET_THRESHOLD',             N'Budget alert',                 N'A project I manage, or a project for my client, crosses a budget alert percent.', N'Projects', 1, 0, 10, NULL),
    ('PROJECT_CREATED_ON_MY_CLIENT', N'New project on my client',     N'Someone adds a project to a client I am the account manager for.', N'Projects', 1, 0, 20, NULL),
    ('TASK_CREATED_ON_MY_PROJECT',   N'New task on my project',       N'Someone adds a task to a project I manage.', N'Tasks', 0, 0, 30, NULL),
    ('TASK_ASSIGNED_TO_ME',          N'Task assigned to me',          N'Someone assigns me a task.', N'Tasks', 1, 0, 40, NULL),
    ('MENTIONED',                    N'Mentions',                     N'Someone @mentions me in a task comment or client note.', N'Tasks', 1, 0, 50, 'REPLY'),
    ('WATCHED_TASK_CHANGED',         N'Tasks I follow',               N'A task I follow gets a comment or changes status.', N'Tasks', 1, 0, 60, NULL),
    ('TIMESHEET_SUBMITTED',          N'Timesheet submitted',          N'A timesheet is waiting for my approval.', N'Time', 1, 0, 70, 'APPROVE_TIMESHEET'),
    ('TIMESHEET_REJECTED',           N'Timesheet sent back',          N'My timesheet was sent back.', N'Time', 1, 0, 80, NULL),
    ('TIMESHEET_DUE',                N'Timesheet reminder',           N'My week is ending and my timesheet isn''t submitted yet.', N'Time', 1, 0, 85, NULL),
    ('INVOICE_PAID',                 N'Invoice paid',                 N'A client pays an invoice for a client I manage.', N'Billing', 0, 0, 90, NULL),
    ('INVOICE_OVERDUE',              N'Invoice overdue',              N'An invoice for a client I manage is past due.', N'Billing', 1, 0, 95, NULL),
    ('BILL_AWAITING_APPROVAL',       N'Bill awaiting approval',       N'A bill or expense report is waiting for my approval.', N'Billing', 1, 0, 100, NULL),
    ('PILO_USAGE_NEAR_LIMIT',        N'Pilo usage near limit',        N'The company has used most of this month''s Pilo reports.', N'Account', 1, 0, 110, NULL),
    ('PLAN_PAYMENT_FAILED',          N'Pillar payment failed',        N'The card on file was declined for the Pillar statement.', N'Account', 1, 1, 120, NULL),
    ('SUPPORT_REPLY',                N'Support replies',              N'Pillar support answers a ticket I opened.', N'Account', 1, 1, 130, NULL)
) AS s (Code, Name, Description, Category, DefaultOn, DefaultEmailOn, SortOrder, ActionKind)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description, Category = s.Category, DefaultOn = s.DefaultOn,
    DefaultEmailOn = s.DefaultEmailOn, SortOrder = s.SortOrder, ActionKind = s.ActionKind
WHEN NOT MATCHED THEN INSERT (Code, Name, Description, Category, DefaultOn, DefaultEmailOn, SortOrder, ActionKind)
    VALUES (s.Code, s.Name, s.Description, s.Category, s.DefaultOn, s.DefaultEmailOn, s.SortOrder, s.ActionKind);

MERGE admin.PiloEmote AS t
USING (VALUES
    ('HELLO', N'Hello', 10), ('WAVE', N'Wave', 20), ('THINKING', N'Thinking', 30), ('CELEBRATE', N'Celebrate', 40),
    ('FOCUSED', N'Focused', 50), ('COFFEE', N'Coffee', 60), ('THUMBS_UP', N'Thumbs up', 70), ('SLEEPY', N'Sleepy', 80)
) AS s (Code, Name, SortOrder)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (Code, Name, SortOrder) VALUES (s.Code, s.Name, s.SortOrder);

-- handoff 22: logins that already signed in or accepted an invite count as verified (only new sign-ups verify by link)
UPDATE c SET EmailVerifiedAt = COALESCE(c.LastLoginAt, c.PasswordChangedAt, c.CreatedAt)
FROM sec.UserCredential AS c
JOIN admin.Tenant AS t ON t.Id = c.TenantId
WHERE c.EmailVerifiedAt IS NULL AND c.PasswordHash IS NOT NULL AND t.Status <> 'SETUP';

-- existing tenants get lookup lists added since they signed up (insert-only; tenant edits are kept)
EXEC lkp.usp_SyncTenantLookups;

-- tenants without an INVOICE email template get the default one
EXEC admin.usp_SeedTenantEmailTemplates;

-- existing tenants get missing roles and newly granted permissions
EXEC sec.usp_SeedTenantRoles;

EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
