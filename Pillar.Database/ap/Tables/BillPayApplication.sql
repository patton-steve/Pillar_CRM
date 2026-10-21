-- Applies part of a bill payment to a bill of the same payee (checked by ap.usp_BillPay_Apply).
-- Unapplying sets ReversedAt; only active rows count.
CREATE TABLE ap.BillPayApplication
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BillPayApplication PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    BillPayId       INT             NOT NULL,
    BillId          INT             NOT NULL,
    AmountApplied   DECIMAL(19,2)   NOT NULL,
    AppliedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_BillPayApplication_AppliedAt DEFAULT (SYSUTCDATETIME()),
    AppliedBy       INT             NULL CONSTRAINT DF_BillPayApplication_AppliedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ReversedAt      DATETIME2(0)    NULL,
    ReversedBy      INT             NULL,
    CONSTRAINT UQ_BillPayApplication_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_BillPayApplication_Amount CHECK (AmountApplied > 0),
    CONSTRAINT FK_BillPayApplication_Pay FOREIGN KEY (TenantId, BillPayId) REFERENCES ap.BillPay (TenantId, Id),
    CONSTRAINT FK_BillPayApplication_Bill FOREIGN KEY (TenantId, BillId) REFERENCES ap.Bill (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_BillPayApplication_Bill ON ap.BillPayApplication (TenantId, BillId) INCLUDE (AmountApplied) WHERE ReversedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_BillPayApplication_Pay ON ap.BillPayApplication (TenantId, BillPayId) INCLUDE (AmountApplied) WHERE ReversedAt IS NULL;
