-- Every charge attempt against a platform statement, successful or not, as reported by the API after calling the processor.
-- Written only by admin.usp_PlatformStatement_RecordPayment.
CREATE TABLE admin.PlatformPayment
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformPayment PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    StatementId         INT             NOT NULL,
    PaymentMethodId     INT             NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    Succeeded           BIT             NOT NULL,
    ProcessorChargeId   VARCHAR(100)    NULL,      -- e.g. pi_... / ch_...
    FailureReason       NVARCHAR(500)   NULL,
    MethodDisplay       NVARCHAR(60)    NULL,      -- snapshot, e.g. "Visa ending 4242"
    AttemptedAt         DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformPayment_AttemptedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_PlatformPayment_Amount CHECK (Amount > 0),
    CONSTRAINT FK_PlatformPayment_Statement FOREIGN KEY (TenantId, StatementId) REFERENCES admin.PlatformStatement (TenantId, Id),
    CONSTRAINT FK_PlatformPayment_Method FOREIGN KEY (TenantId, PaymentMethodId) REFERENCES admin.TenantPaymentMethod (TenantId, Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_PlatformPayment_Charge ON admin.PlatformPayment (ProcessorChargeId) WHERE ProcessorChargeId IS NOT NULL;
GO
CREATE NONCLUSTERED INDEX IX_PlatformPayment_Statement ON admin.PlatformPayment (TenantId, StatementId);
