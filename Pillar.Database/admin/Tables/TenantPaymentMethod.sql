-- The tenant's card (or bank account) on file for Pillar's monthly charge. Only the processor's tokens and display details
-- are stored; card numbers never reach Pillar (the UI collects them with the processor's hosted form, e.g. Stripe Elements).
-- One IsDefault method is charged; tenants add and remove methods from Settings > Billing.
CREATE TABLE admin.TenantPaymentMethod
(
    Id                          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TenantPaymentMethod PRIMARY KEY CLUSTERED,
    TenantId                    INT             NOT NULL,
    Processor                   VARCHAR(20)     NOT NULL CONSTRAINT DF_TenantPaymentMethod_Processor DEFAULT ('STRIPE'),
    ProcessorCustomerId         VARCHAR(100)    NOT NULL,      -- e.g. cus_...
    ProcessorPaymentMethodId    VARCHAR(100)    NOT NULL,      -- e.g. pm_...
    MethodType                  VARCHAR(10)     NOT NULL,      -- CARD, ACH
    Brand                       NVARCHAR(30)    NULL,          -- Visa, Mastercard, bank name
    Last4                       CHAR(4)         NULL,
    ExpMonth                    TINYINT         NULL,
    ExpYear                     SMALLINT        NULL,
    IsDefault                   BIT             NOT NULL CONSTRAINT DF_TenantPaymentMethod_IsDefault DEFAULT (0),
    IsActive                    BIT             NOT NULL CONSTRAINT DF_TenantPaymentMethod_IsActive DEFAULT (1),
    CreatedAt                   DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantPaymentMethod_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy                   INT             NULL CONSTRAINT DF_TenantPaymentMethod_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt                  DATETIME2(0)    NULL,
    ModifiedBy                  INT             NULL,
    CONSTRAINT UQ_TenantPaymentMethod_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_TenantPaymentMethod_Token UNIQUE (Processor, ProcessorPaymentMethodId),
    CONSTRAINT CK_TenantPaymentMethod_MethodType CHECK (MethodType IN ('CARD', 'ACH')),
    CONSTRAINT CK_TenantPaymentMethod_Exp CHECK (ExpMonth IS NULL OR ExpMonth BETWEEN 1 AND 12),
    CONSTRAINT FK_TenantPaymentMethod_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_TenantPaymentMethod_Default ON admin.TenantPaymentMethod (TenantId) WHERE IsDefault = 1 AND IsActive = 1;
