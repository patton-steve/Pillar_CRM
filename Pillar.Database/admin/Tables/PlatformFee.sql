-- Pillar's fee on each issued invoice: FeeRate x pre-tax subtotal, capped by Plan.PerInvoiceCap.
-- Written by ar.usp_Invoice_Issue; a void adds a negative REVERSAL row (rows are never updated for amounts).
-- Rolled up monthly onto admin.PlatformStatement: PlatformStatementId is set when billed (FEE rows ACCRUED -> BILLED -> PAID;
-- REVERSAL rows keep their status). Never shown on the tenant's own invoices.
CREATE TABLE admin.PlatformFee
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformFee PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    InvoiceId           INT             NOT NULL,
    FeeBaseAmount       DECIMAL(19,2)   NOT NULL,
    FeeRate             DECIMAL(9,6)    NOT NULL,
    FeeAmount           DECIMAL(19,2)   NOT NULL,
    FeeStatus           VARCHAR(10)     NOT NULL CONSTRAINT DF_PlatformFee_FeeStatus DEFAULT ('ACCRUED'),
    ReversalOfFeeId     INT             NULL,
    PlatformStatementId INT             NULL,      -- NULL = not yet billed
    AccruedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformFee_AccruedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_PlatformFee_Status CHECK (FeeStatus IN ('ACCRUED', 'BILLED', 'PAID', 'REVERSAL')),
    CONSTRAINT CK_PlatformFee_Reversal CHECK ((FeeStatus = 'REVERSAL' AND ReversalOfFeeId IS NOT NULL) OR (FeeStatus <> 'REVERSAL' AND ReversalOfFeeId IS NULL)),
    CONSTRAINT FK_PlatformFee_Invoice FOREIGN KEY (TenantId, InvoiceId) REFERENCES ar.Invoice (TenantId, Id),
    CONSTRAINT FK_PlatformFee_Reversal FOREIGN KEY (ReversalOfFeeId) REFERENCES admin.PlatformFee (Id),
    CONSTRAINT FK_PlatformFee_Statement FOREIGN KEY (TenantId, PlatformStatementId) REFERENCES admin.PlatformStatement (TenantId, Id)
);
GO
-- one original fee and at most one reversal per invoice
CREATE UNIQUE NONCLUSTERED INDEX UX_PlatformFee_Invoice ON admin.PlatformFee (TenantId, InvoiceId) WHERE ReversalOfFeeId IS NULL;
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_PlatformFee_Reversal ON admin.PlatformFee (ReversalOfFeeId) WHERE ReversalOfFeeId IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_PlatformFee_Unbilled ON admin.PlatformFee (TenantId, AccruedAt) INCLUDE (FeeAmount) WHERE PlatformStatementId IS NULL;
