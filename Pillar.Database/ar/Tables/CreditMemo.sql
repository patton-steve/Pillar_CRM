-- A credit issued to a client (billing error, goodwill, dispute). Numbered at creation from NumberSequence 'CREDITMEMO'.
-- Applied to invoices like a payment, or refunded. Does not change the platform fee (only an invoice void reverses it).
CREATE TABLE ar.CreditMemo
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CreditMemo PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CreditMemo_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    ClientId            INT             NOT NULL,
    CreditMemoNumber    NVARCHAR(50)    NOT NULL,
    CreditDate          DATE            NOT NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    Reason              NVARCHAR(500)   NOT NULL,
    SourceInvoiceId     INT             NULL,      -- the invoice being credited, if any
    AmountApplied       DECIMAL(19,2)   NOT NULL CONSTRAINT DF_CreditMemo_AmountApplied DEFAULT (0),
    AmountRefunded      DECIMAL(19,2)   NOT NULL CONSTRAINT DF_CreditMemo_AmountRefunded DEFAULT (0),
    UnappliedAmount     AS CONVERT(DECIMAL(19,2), Amount - AmountApplied - AmountRefunded) PERSISTED,
    VoidedAt            DATETIME2(0)    NULL,
    VoidedBy            INT             NULL,
    VoidReason          NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_CreditMemo_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_CreditMemo_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_CreditMemo_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_CreditMemo_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_CreditMemo_Tenant_Client_Id UNIQUE (TenantId, ClientId, Id),
    CONSTRAINT UQ_CreditMemo_Tenant_Number UNIQUE (TenantId, CreditMemoNumber),
    CONSTRAINT CK_CreditMemo_Amount CHECK (Amount > 0),
    CONSTRAINT CK_CreditMemo_Balance CHECK (AmountApplied >= 0 AND AmountRefunded >= 0 AND AmountApplied + AmountRefunded <= Amount),
    CONSTRAINT FK_CreditMemo_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    CONSTRAINT FK_CreditMemo_SourceInvoice FOREIGN KEY (TenantId, ClientId, SourceInvoiceId) REFERENCES ar.Invoice (TenantId, ClientId, Id)
);
