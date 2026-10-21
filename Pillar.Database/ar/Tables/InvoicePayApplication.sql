-- Applies part of a payment or credit memo to an invoice. Many-to-many: one payment can cover several invoices,
-- one invoice can take several payments and credits. Unapplying sets ReversedAt (rows are kept for audit);
-- only rows with ReversedAt NULL count toward Invoice.AmountPaid and the source's AmountApplied.
CREATE TABLE ar.InvoicePayApplication
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoicePayApplication PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    ClientId        INT             NOT NULL,
    InvoiceId       INT             NOT NULL,
    InvoicePayId    INT             NULL,
    CreditMemoId    INT             NULL,
    AmountApplied   DECIMAL(19,2)   NOT NULL,
    AppliedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoicePayApplication_AppliedAt DEFAULT (SYSUTCDATETIME()),
    AppliedBy       INT             NULL CONSTRAINT DF_InvoicePayApplication_AppliedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ReversedAt      DATETIME2(0)    NULL,
    ReversedBy      INT             NULL,
    CONSTRAINT UQ_InvoicePayApplication_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_InvoicePayApplication_Amount CHECK (AmountApplied > 0),
    CONSTRAINT CK_InvoicePayApplication_Source CHECK ((InvoicePayId IS NOT NULL AND CreditMemoId IS NULL) OR (InvoicePayId IS NULL AND CreditMemoId IS NOT NULL)),
    -- invoice, payment and credit must all belong to the same client
    CONSTRAINT FK_InvoicePayApplication_Invoice FOREIGN KEY (TenantId, ClientId, InvoiceId) REFERENCES ar.Invoice (TenantId, ClientId, Id),
    CONSTRAINT FK_InvoicePayApplication_Pay FOREIGN KEY (TenantId, ClientId, InvoicePayId) REFERENCES ar.InvoicePay (TenantId, ClientId, Id),
    CONSTRAINT FK_InvoicePayApplication_Credit FOREIGN KEY (TenantId, ClientId, CreditMemoId) REFERENCES ar.CreditMemo (TenantId, ClientId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_InvoicePayApplication_Invoice ON ar.InvoicePayApplication (TenantId, InvoiceId) INCLUDE (AmountApplied) WHERE ReversedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_InvoicePayApplication_Pay ON ar.InvoicePayApplication (TenantId, InvoicePayId) INCLUDE (AmountApplied) WHERE ReversedAt IS NULL AND InvoicePayId IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_InvoicePayApplication_Credit ON ar.InvoicePayApplication (TenantId, CreditMemoId) INCLUDE (AmountApplied) WHERE ReversedAt IS NULL AND CreditMemoId IS NOT NULL;
