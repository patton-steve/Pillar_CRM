-- Money received from a client. Applied to one or more invoices through ar.InvoicePayApplication;
-- whatever is neither applied nor refunded stays on the client as a credit (UnappliedAmount).
-- A bounced or mistaken payment is voided (ar.usp_InvoicePay_Void), never deleted.
CREATE TABLE ar.InvoicePay
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoicePay PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_InvoicePay_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    ClientId            INT             NOT NULL,
    PaymentDate         DATE            NOT NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    PaymentMethodId     INT             NOT NULL,
    ReferenceNumber     NVARCHAR(100)   NULL,      -- check number, ACH trace, card transaction id
    Memo                NVARCHAR(500)   NULL,
    AmountApplied       DECIMAL(19,2)   NOT NULL CONSTRAINT DF_InvoicePay_AmountApplied DEFAULT (0),   -- maintained by apply/unapply
    AmountRefunded      DECIMAL(19,2)   NOT NULL CONSTRAINT DF_InvoicePay_AmountRefunded DEFAULT (0),  -- maintained by ar.usp_Refund_Create
    UnappliedAmount     AS CONVERT(DECIMAL(19,2), Amount - AmountApplied - AmountRefunded) PERSISTED,
    VoidedAt            DATETIME2(0)    NULL,
    VoidedBy            INT             NULL,
    VoidReason          NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoicePay_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_InvoicePay_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_InvoicePay_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_InvoicePay_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_InvoicePay_Tenant_Client_Id UNIQUE (TenantId, ClientId, Id),
    CONSTRAINT CK_InvoicePay_Amount CHECK (Amount > 0),
    CONSTRAINT CK_InvoicePay_Balance CHECK (AmountApplied >= 0 AND AmountRefunded >= 0 AND AmountApplied + AmountRefunded <= Amount),
    CONSTRAINT FK_InvoicePay_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    CONSTRAINT FK_InvoicePay_PaymentMethod FOREIGN KEY (TenantId, PaymentMethodId) REFERENCES lkp.PaymentMethod (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_InvoicePay_Client ON ar.InvoicePay (TenantId, ClientId, PaymentDate) INCLUDE (UnappliedAmount) WHERE VoidedAt IS NULL;
