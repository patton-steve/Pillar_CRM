-- Money returned to a client out of an unapplied payment or credit memo.
CREATE TABLE ar.Refund
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Refund PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    ClientId            INT             NOT NULL,
    InvoicePayId        INT             NULL,
    CreditMemoId        INT             NULL,
    RefundDate          DATE            NOT NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    PaymentMethodId     INT             NOT NULL,
    ReferenceNumber     NVARCHAR(100)   NULL,
    Memo                NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_Refund_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_Refund_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT UQ_Refund_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_Refund_Amount CHECK (Amount > 0),
    CONSTRAINT CK_Refund_Source CHECK ((InvoicePayId IS NOT NULL AND CreditMemoId IS NULL) OR (InvoicePayId IS NULL AND CreditMemoId IS NOT NULL)),
    CONSTRAINT FK_Refund_Pay FOREIGN KEY (TenantId, ClientId, InvoicePayId) REFERENCES ar.InvoicePay (TenantId, ClientId, Id),
    CONSTRAINT FK_Refund_Credit FOREIGN KEY (TenantId, ClientId, CreditMemoId) REFERENCES ar.CreditMemo (TenantId, ClientId, Id),
    CONSTRAINT FK_Refund_PaymentMethod FOREIGN KEY (TenantId, PaymentMethodId) REFERENCES lkp.PaymentMethod (TenantId, Id)
);
