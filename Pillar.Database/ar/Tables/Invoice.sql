-- An invoice to one client billing profile. Drafts are editable and unnumbered; issuing (ar.usp_Invoice_Issue)
-- assigns the number, snapshots bill-to/terms, locks lines and time, and accrues the platform fee.
-- Issued invoices change only through payments or ar.usp_Invoice_Void.
CREATE TABLE ar.Invoice
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Invoice PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Invoice_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    ClientId            INT             NOT NULL,
    BillingProfileId    INT             NOT NULL,
    InvoiceRunId        INT             NULL,      -- NULL = one-off manual invoice
    InvoiceNumber       NVARCHAR(50)    NULL,      -- assigned at issue from admin.NumberSequence 'INVOICE'
    InvoiceStatusId     INT             NOT NULL,
    InvoiceDate         DATE            NULL,      -- defaults to the tenant's today at issue
    DueDate             DATE            NULL,      -- InvoiceDate + PaymentTerm.DueDays, set at issue
    PaymentTermId       INT             NOT NULL,
    PeriodStart         DATE            NULL,
    PeriodEnd           DATE            NULL,
    PoNumber            NVARCHAR(50)    NULL,
    -- snapshot of the billing profile, refreshed at issue
    BillToContactId     INT             NULL,
    BillToName          NVARCHAR(200)   NULL,
    BillToEmail         NVARCHAR(254)   NULL,
    BillToAddress       NVARCHAR(1000)  NULL,      -- formatted block
    ClientName          NVARCHAR(200)   NULL,
    InvoiceLayoutId     INT             NULL,      -- set at issue: profile layout, else tenant default
    RemitProfileId      INT             NULL,      -- set at issue: profile remit, else tenant default
    InvoiceNotes        NVARCHAR(1000)  NULL,
    TaxExempt           BIT             NOT NULL CONSTRAINT DF_Invoice_TaxExempt DEFAULT (0),
    TaxRate             DECIMAL(9,6)    NOT NULL CONSTRAINT DF_Invoice_TaxRate DEFAULT (0),
    SubTotal            DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Invoice_SubTotal DEFAULT (0),
    TaxAmount           DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Invoice_TaxAmount DEFAULT (0),
    Total               AS CONVERT(DECIMAL(19,2), SubTotal + TaxAmount) PERSISTED,
    AmountPaid          DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Invoice_AmountPaid DEFAULT (0),  -- maintained by payment application
    BalanceDue          AS CONVERT(DECIMAL(19,2), SubTotal + TaxAmount - AmountPaid) PERSISTED,
    IssuedAt            DATETIME2(0)    NULL,
    IssuedBy            INT             NULL,
    VoidedAt            DATETIME2(0)    NULL,
    VoidedBy            INT             NULL,
    VoidReason          NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_Invoice_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_Invoice_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_Invoice_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_Invoice_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Invoice_Tenant_Client_Id UNIQUE (TenantId, ClientId, Id),
    CONSTRAINT CK_Invoice_TaxRate CHECK (TaxRate >= 0 AND TaxRate < 1),
    CONSTRAINT CK_Invoice_AmountPaid CHECK (AmountPaid >= 0),
    CONSTRAINT CK_Invoice_DueDate CHECK (DueDate IS NULL OR InvoiceDate IS NULL OR DueDate >= InvoiceDate),
    CONSTRAINT FK_Invoice_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    CONSTRAINT FK_Invoice_BillingProfile FOREIGN KEY (TenantId, ClientId, BillingProfileId)
        REFERENCES crm.ClientBillingProfile (TenantId, ClientId, Id),
    CONSTRAINT FK_Invoice_Run FOREIGN KEY (TenantId, InvoiceRunId) REFERENCES ar.InvoiceRun (TenantId, Id),
    CONSTRAINT FK_Invoice_Status FOREIGN KEY (TenantId, InvoiceStatusId) REFERENCES lkp.InvoiceStatus (TenantId, Id),
    CONSTRAINT FK_Invoice_PaymentTerm FOREIGN KEY (TenantId, PaymentTermId) REFERENCES lkp.PaymentTerm (TenantId, Id),
    CONSTRAINT FK_Invoice_BillToContact FOREIGN KEY (TenantId, ClientId, BillToContactId)
        REFERENCES crm.Contact (TenantId, ClientId, Id),
    CONSTRAINT FK_Invoice_InvoiceLayout FOREIGN KEY (TenantId, InvoiceLayoutId) REFERENCES ar.InvoiceLayout (TenantId, Id),
    CONSTRAINT FK_Invoice_RemitProfile FOREIGN KEY (TenantId, RemitProfileId) REFERENCES admin.RemitProfile (TenantId, Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_Invoice_Tenant_Number ON ar.Invoice (TenantId, InvoiceNumber) WHERE InvoiceNumber IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_Invoice_Client_Status ON ar.Invoice (TenantId, ClientId, InvoiceStatusId) INCLUDE (DueDate, BalanceDue);
GO
CREATE NONCLUSTERED INDEX IX_Invoice_Run ON ar.Invoice (TenantId, InvoiceRunId) WHERE InvoiceRunId IS NOT NULL;
