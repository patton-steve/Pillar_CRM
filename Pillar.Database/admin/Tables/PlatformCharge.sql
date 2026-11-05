-- One-time charges Pillar adds to a tenant (handoff 26): onboarding, a data import, a custom RDL layout or anything else.
--   BillOn NEXT_STATEMENT  billed as a SERVICE line on the statement for the month of ChargeDate (or the first one after it)
--   BillOn CHARGE_NOW      the API charges the card on file now and records it (admin.usp_PlatformCharge_RecordPayment);
--                          a failed charge moves to NEXT_STATEMENT
--   Status PENDING (not billed yet), BILLED (on a statement), PAID (charged now), CANCELLED
-- Pillar-only data: outside RLS; tenants see a charge as its statement line.
CREATE TABLE admin.PlatformCharge
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformCharge PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Kind            VARCHAR(12)     NOT NULL,
    Description     NVARCHAR(200)   NOT NULL,
    Amount          DECIMAL(19,2)   NOT NULL,
    BillOn          VARCHAR(15)     NOT NULL CONSTRAINT DF_PlatformCharge_BillOn DEFAULT ('NEXT_STATEMENT'),
    ChargeDate      DATE            NOT NULL,
    Status          VARCHAR(10)     NOT NULL CONSTRAINT DF_PlatformCharge_Status DEFAULT ('PENDING'),
    StatementId     INT             NULL,
    PaymentMethodId INT             NULL,
    ProcessorChargeId VARCHAR(100)  NULL,
    PaidAt          DATETIME2(0)    NULL,
    Note            NVARCHAR(500)   NULL,
    Reason          NVARCHAR(500)   NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformCharge_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_PlatformCharge_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CancelledAt     DATETIME2(0)    NULL,
    CONSTRAINT CK_PlatformCharge_Kind CHECK (Kind = 'ONBOARDING' OR Kind = 'IMPORT' OR Kind = 'CUSTOM_RDL' OR Kind = 'OTHER'),
    CONSTRAINT CK_PlatformCharge_BillOn CHECK (BillOn = 'NEXT_STATEMENT' OR BillOn = 'CHARGE_NOW'),
    CONSTRAINT CK_PlatformCharge_Status CHECK (Status = 'PENDING' OR Status = 'BILLED' OR Status = 'PAID' OR Status = 'CANCELLED'),
    CONSTRAINT CK_PlatformCharge_Amount CHECK (Amount > 0),
    CONSTRAINT FK_PlatformCharge_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_PlatformCharge_Statement FOREIGN KEY (TenantId, StatementId) REFERENCES admin.PlatformStatement (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_PlatformCharge_Tenant ON admin.PlatformCharge (TenantId, Status, ChargeDate);
