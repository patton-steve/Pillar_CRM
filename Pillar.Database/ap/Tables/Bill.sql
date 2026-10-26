-- Money owed. Two kinds share this table so approval, payment and rebilling work the same way:
--   vendor bill    VendorId set      (a vendor's invoice to the tenant)
--   expense report PayeeUserId set   (a user's out-of-pocket expenses to reimburse; needs Feature.ExpenseReports)
-- Flow: DRAFT -> SUBMITTED (when AP.RequireApproval) -> OPEN -> PARTIAL -> PAID, or VOID.
-- BillNumber is internal (NumberSequence 'BILL' or 'EXPENSE'); VendorInvoiceNumber is the vendor's own number.
-- Weekly expenses (Steve 2026-10-22): TimesheetId ties a user's expense report to one timesheet week. ap.usp_Expense_Save
-- creates it with the week's first expense, and it is submitted, approved and sent back with the timesheet, never on its own.
CREATE TABLE ap.Bill
(
    Id                      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Bill PRIMARY KEY CLUSTERED,
    PublicId                UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Bill_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId                INT             NOT NULL,
    VendorId                INT             NULL,
    PayeeUserId             INT             NULL,
    BillNumber              NVARCHAR(50)    NOT NULL,
    VendorInvoiceNumber     NVARCHAR(50)    NULL,
    BillDate                DATE            NOT NULL,
    DueDate                 DATE            NULL,
    PaymentTermId           INT             NULL,
    BillStatusId            INT             NOT NULL,
    Description             NVARCHAR(500)   NULL,
    SubTotal                DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Bill_SubTotal DEFAULT (0),
    TaxAmount               DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Bill_TaxAmount DEFAULT (0),
    Total                   AS CONVERT(DECIMAL(19,2), SubTotal + TaxAmount) PERSISTED,
    AmountPaid              DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Bill_AmountPaid DEFAULT (0),
    BalanceDue              AS CONVERT(DECIMAL(19,2), SubTotal + TaxAmount - AmountPaid) PERSISTED,
    SubmittedAt             DATETIME2(0)    NULL,
    ApprovedAt              DATETIME2(0)    NULL,
    ApprovedBy              INT             NULL,
    RejectedAt              DATETIME2(0)    NULL,
    RejectedBy              INT             NULL,
    RejectedReason          NVARCHAR(500)   NULL,
    VoidedAt                DATETIME2(0)    NULL,
    VoidedBy                INT             NULL,
    VoidReason              NVARCHAR(500)   NULL,
    CreatedAt               DATETIME2(0)    NOT NULL CONSTRAINT DF_Bill_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy               INT             NULL CONSTRAINT DF_Bill_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt              DATETIME2(0)    NULL,
    ModifiedBy              INT             NULL,
    RowVer                  ROWVERSION      NOT NULL,
    TimesheetId             INT             NULL,      -- weekly expense report: the payee's timesheet week. Last so a publish appends it.
    CONSTRAINT UQ_Bill_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_Bill_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Bill_Tenant_Number UNIQUE (TenantId, BillNumber),
    CONSTRAINT CK_Bill_Payee CHECK ((VendorId IS NOT NULL AND PayeeUserId IS NULL) OR (VendorId IS NULL AND PayeeUserId IS NOT NULL)),
    CONSTRAINT CK_Bill_AmountPaid CHECK (AmountPaid >= 0),
    CONSTRAINT FK_Bill_Vendor FOREIGN KEY (TenantId, VendorId) REFERENCES ap.Vendor (TenantId, Id),
    CONSTRAINT FK_Bill_PaymentTerm FOREIGN KEY (TenantId, PaymentTermId) REFERENCES lkp.PaymentTerm (TenantId, Id),
    CONSTRAINT FK_Bill_Status FOREIGN KEY (TenantId, BillStatusId) REFERENCES lkp.BillStatus (TenantId, Id),
    CONSTRAINT FK_Bill_PayeeUser FOREIGN KEY (TenantId, PayeeUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT CK_Bill_Timesheet CHECK (TimesheetId IS NULL OR PayeeUserId IS NOT NULL),
    CONSTRAINT FK_Bill_Timesheet FOREIGN KEY (TenantId, TimesheetId) REFERENCES crm.Timesheet (TenantId, Id)
);
GO
-- the same vendor invoice can't be entered twice
CREATE UNIQUE NONCLUSTERED INDEX UX_Bill_VendorInvoice ON ap.Bill (TenantId, VendorId, VendorInvoiceNumber)
    WHERE VendorId IS NOT NULL AND VendorInvoiceNumber IS NOT NULL AND VoidedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_Bill_Status_Due ON ap.Bill (TenantId, BillStatusId, DueDate) INCLUDE (BalanceDue);

GO
-- one live expense report per timesheet week
CREATE UNIQUE NONCLUSTERED INDEX UX_Bill_Timesheet ON ap.Bill (TenantId, TimesheetId)
    WHERE TimesheetId IS NOT NULL AND VoidedAt IS NULL;
