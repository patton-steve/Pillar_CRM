-- Pillar's monthly bill to a tenant for its platform fees. Created by admin.usp_PlatformStatement_Generate (platform job, 1st of the month),
-- charged to the tenant's card on file by the API, and settled through admin.usp_PlatformStatement_RecordPayment.
-- Tenants can read their own statements (Settings > Billing); only Pillar's procs write them.
-- Status: OPEN (to be charged), PAST_DUE (a charge failed), PAID, VOID. A statement with nothing due is PAID at creation.
CREATE TABLE admin.PlatformStatement
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformStatement PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_PlatformStatement_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    StatementNumber     VARCHAR(20)     NOT NULL,      -- PS-yyyyMM-TTTTT
    PeriodStart         DATE            NOT NULL,
    PeriodEnd           DATE            NOT NULL,
    StatementDate       DATE            NOT NULL,
    DueDate             DATE            NOT NULL,      -- charged on the statement date
    Status              VARCHAR(10)     NOT NULL CONSTRAINT DF_PlatformStatement_Status DEFAULT ('OPEN'),
    FeeTotal            DECIMAL(19,2)   NOT NULL CONSTRAINT DF_PlatformStatement_FeeTotal DEFAULT (0),          -- FEE + REVERSAL lines
    MinimumAdjustment   DECIMAL(19,2)   NOT NULL CONSTRAINT DF_PlatformStatement_MinimumAdjustment DEFAULT (0), -- top-up to the monthly minimum
    CreditApplied       DECIMAL(19,2)   NOT NULL CONSTRAINT DF_PlatformStatement_CreditApplied DEFAULT (0),     -- negative: credit carried from the prior statement
    AmountDue           DECIMAL(19,2)   NOT NULL,
    CreditForward       DECIMAL(19,2)   NOT NULL CONSTRAINT DF_PlatformStatement_CreditForward DEFAULT (0),     -- credit left over (net was negative), applied next month
    AmountPaid          DECIMAL(19,2)   NOT NULL CONSTRAINT DF_PlatformStatement_AmountPaid DEFAULT (0),
    BalanceDue          AS CONVERT(DECIMAL(19,2), AmountDue - AmountPaid) PERSISTED,
    PaidAt              DATETIME2(0)    NULL,
    FailedAttempts      INT             NOT NULL CONSTRAINT DF_PlatformStatement_FailedAttempts DEFAULT (0),
    LastAttemptAt       DATETIME2(0)    NULL,
    VoidedAt            DATETIME2(0)    NULL,
    VoidReason          NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformStatement_CreatedAt DEFAULT (SYSUTCDATETIME()),
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_PlatformStatement_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_PlatformStatement_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_PlatformStatement_Status CHECK (Status IN ('OPEN', 'PAST_DUE', 'PAID', 'VOID')),
    CONSTRAINT CK_PlatformStatement_Period CHECK (PeriodEnd >= PeriodStart),
    CONSTRAINT CK_PlatformStatement_Amounts CHECK (AmountDue >= 0 AND AmountPaid >= 0 AND CreditForward >= 0 AND CreditApplied <= 0),
    CONSTRAINT FK_PlatformStatement_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
-- one live statement per tenant per month; a voided one can be regenerated
CREATE UNIQUE NONCLUSTERED INDEX UX_PlatformStatement_Tenant_Period ON admin.PlatformStatement (TenantId, PeriodStart) WHERE Status <> 'VOID';
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_PlatformStatement_Number ON admin.PlatformStatement (StatementNumber) WHERE Status <> 'VOID';
GO
CREATE NONCLUSTERED INDEX IX_PlatformStatement_Unpaid ON admin.PlatformStatement (Status, DueDate) INCLUDE (TenantId, BalanceDue) WHERE Status IN ('OPEN', 'PAST_DUE');
