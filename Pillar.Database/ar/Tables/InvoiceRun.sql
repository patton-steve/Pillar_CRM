-- One "Create invoices" batch (manual click or the nightly AUTO_DRAFT job). Its invoices are created as
-- drafts and can be reviewed, issued or deleted together.
CREATE TABLE ar.InvoiceRun
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceRun PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_InvoiceRun_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    PeriodEnd       DATE            NOT NULL,  -- approved time with WorkDate <= PeriodEnd is included
    ClientId        INT             NULL,      -- optional filters
    ProjectId       INT             NULL,
    Source          VARCHAR(10)     NOT NULL CONSTRAINT DF_InvoiceRun_Source DEFAULT ('MANUAL'),
    InvoiceCount    INT             NOT NULL CONSTRAINT DF_InvoiceRun_InvoiceCount DEFAULT (0),
    ExceptionCount  INT             NOT NULL CONSTRAINT DF_InvoiceRun_ExceptionCount DEFAULT (0),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceRun_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_InvoiceRun_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT UQ_InvoiceRun_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_InvoiceRun_Source CHECK (Source IN ('MANUAL', 'SCHEDULED')),
    CONSTRAINT FK_InvoiceRun_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
