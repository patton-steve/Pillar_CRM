-- The tenant's card (or bank account) on file for Pillar's monthly charge. Only the processor's tokens and display details
-- are stored; card numbers never reach Pillar (the UI collects them with the processor's hosted form, e.g. Stripe Elements).
-- One IsDefault method is charged; tenants add and remove methods from Settings > Billing.
-- Verified (handoff 22): the card passed the processor's setup flow (Stripe SetupIntent: a $0 authorization and 3-D Secure)
-- when it was added. The API sets Verified, VerifiedAt and ProcessorSetupId when the SetupIntent succeeds.
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
    Verified                    BIT             NOT NULL CONSTRAINT DF_TenantPaymentMethod_Verified DEFAULT (0),   -- handoff 22: appended
    VerifiedAt                  DATETIME2(0)    NULL,
    ProcessorSetupId            VARCHAR(100)    NULL,          -- e.g. seti_...
    CONSTRAINT UQ_TenantPaymentMethod_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_TenantPaymentMethod_Token UNIQUE (Processor, ProcessorPaymentMethodId),
    CONSTRAINT CK_TenantPaymentMethod_MethodType CHECK (MethodType IN ('CARD', 'ACH')),
    CONSTRAINT CK_TenantPaymentMethod_Exp CHECK (ExpMonth IS NULL OR ExpMonth BETWEEN 1 AND 12),
    CONSTRAINT CK_TenantPaymentMethod_Verified CHECK (Verified = 0 OR VerifiedAt IS NOT NULL),
    CONSTRAINT FK_TenantPaymentMethod_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_TenantPaymentMethod_Default ON admin.TenantPaymentMethod (TenantId) WHERE IsDefault = 1 AND IsActive = 1;
