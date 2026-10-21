-- Money paid to a vendor, or a reimbursement to a user. Applied to bills through ap.BillPayApplication.
CREATE TABLE ap.BillPay
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BillPay PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_BillPay_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    VendorId            INT             NULL,
    PayeeUserId         INT             NULL,
    PaymentDate         DATE            NOT NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    PaymentMethodId     INT             NOT NULL,
    ReferenceNumber     NVARCHAR(100)   NULL,      -- check number, ACH trace
    Memo                NVARCHAR(500)   NULL,
    AmountApplied       DECIMAL(19,2)   NOT NULL CONSTRAINT DF_BillPay_AmountApplied DEFAULT (0),
    UnappliedAmount     AS CONVERT(DECIMAL(19,2), Amount - AmountApplied) PERSISTED,
    VoidedAt            DATETIME2(0)    NULL,
    VoidedBy            INT             NULL,
    VoidReason          NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_BillPay_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_BillPay_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_BillPay_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_BillPay_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_BillPay_Payee CHECK ((VendorId IS NOT NULL AND PayeeUserId IS NULL) OR (VendorId IS NULL AND PayeeUserId IS NOT NULL)),
    CONSTRAINT CK_BillPay_Amount CHECK (Amount > 0 AND AmountApplied >= 0 AND AmountApplied <= Amount),
    CONSTRAINT FK_BillPay_Vendor FOREIGN KEY (TenantId, VendorId) REFERENCES ap.Vendor (TenantId, Id),
    CONSTRAINT FK_BillPay_PaymentMethod FOREIGN KEY (TenantId, PaymentMethodId) REFERENCES lkp.PaymentMethod (TenantId, Id),
    CONSTRAINT FK_BillPay_PayeeUser FOREIGN KEY (TenantId, PayeeUserId) REFERENCES sec.AppUser (TenantId, Id)
);
