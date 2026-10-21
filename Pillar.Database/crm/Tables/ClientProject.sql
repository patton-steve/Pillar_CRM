-- A body of work for a client. Separates billing type and holds rates.
-- PaymentTermId NULL = inherit live from the billing profile; a value is an explicit override.
-- Invoice generation groups by (BillingProfileId, effective term) so one invoice never mixes terms.
-- BillingProfileId is required; the API defaults it to the client's default profile.
CREATE TABLE crm.ClientProject
(
    Id                      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientProject PRIMARY KEY CLUSTERED,
    PublicId                UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ClientProject_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId                INT             NOT NULL,
    ClientId                INT             NOT NULL,
    BillingProfileId        INT             NOT NULL,
    ProjectCode             NVARCHAR(20)    NOT NULL,
    Name                    NVARCHAR(200)   NOT NULL,
    Description             NVARCHAR(MAX)   NULL,
    ProjectTypeId           INT             NOT NULL,  -- supplies the task key prefix (PM-118); its DefaultBillingTypeId pre-fills BillingTypeId
    BillingTypeId           INT             NOT NULL,
    ProjectStatusId         INT             NOT NULL,
    PaymentTermId           INT             NULL,
    InvoiceFrequencyId      INT             NULL,
    DefaultRate             DECIMAL(19,4)   NULL,      -- used when no crm.ProjectRate row applies
    FixedFeeAmount          DECIMAL(19,4)   NULL,      -- FIXED: total fee; RETAINER: amount per period
    BudgetHours             DECIMAL(9,2)    NULL,
    BudgetAmount            DECIMAL(19,4)   NULL,      -- NTE: the cap
    StartDate               DATE            NULL,
    EndDate                 DATE            NULL,
    PoNumber                NVARCHAR(50)    NULL,      -- prints on invoice
    ProjectManagerUserId    INT             NULL,
    IsBillable              BIT             NOT NULL CONSTRAINT DF_ClientProject_IsBillable DEFAULT (1),  -- default for new tasks
    DeletedAt               DATETIME2(0)    NULL,
    CreatedAt               DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientProject_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy               INT             NULL CONSTRAINT DF_ClientProject_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt              DATETIME2(0)    NULL,
    ModifiedBy              INT             NULL,
    RowVer                  ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ClientProject_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_ClientProject_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_ClientProject_Tenant_Client_Id UNIQUE (TenantId, ClientId, Id),
    CONSTRAINT UQ_ClientProject_Client_Code UNIQUE (TenantId, ClientId, ProjectCode),
    CONSTRAINT CK_ClientProject_Dates CHECK (EndDate IS NULL OR StartDate IS NULL OR EndDate >= StartDate),
    CONSTRAINT CK_ClientProject_Amounts CHECK (
        (DefaultRate IS NULL OR DefaultRate >= 0) AND (FixedFeeAmount IS NULL OR FixedFeeAmount >= 0)
        AND (BudgetHours IS NULL OR BudgetHours >= 0) AND (BudgetAmount IS NULL OR BudgetAmount >= 0)),
    CONSTRAINT FK_ClientProject_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    -- profile must belong to this client
    CONSTRAINT FK_ClientProject_BillingProfile FOREIGN KEY (TenantId, ClientId, BillingProfileId)
        REFERENCES crm.ClientBillingProfile (TenantId, ClientId, Id),
    CONSTRAINT FK_ClientProject_ProjectType FOREIGN KEY (TenantId, ProjectTypeId) REFERENCES lkp.ProjectType (TenantId, Id),
    CONSTRAINT FK_ClientProject_BillingType FOREIGN KEY (TenantId, BillingTypeId) REFERENCES lkp.BillingType (TenantId, Id),
    CONSTRAINT FK_ClientProject_ProjectStatus FOREIGN KEY (TenantId, ProjectStatusId) REFERENCES lkp.ProjectStatus (TenantId, Id),
    CONSTRAINT FK_ClientProject_PaymentTerm FOREIGN KEY (TenantId, PaymentTermId) REFERENCES lkp.PaymentTerm (TenantId, Id),
    CONSTRAINT FK_ClientProject_InvoiceFrequency FOREIGN KEY (TenantId, InvoiceFrequencyId) REFERENCES lkp.InvoiceFrequency (TenantId, Id),
    CONSTRAINT FK_ClientProject_ProjectManager FOREIGN KEY (TenantId, ProjectManagerUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_ClientProject_BillingProfile ON crm.ClientProject (TenantId, BillingProfileId) WHERE DeletedAt IS NULL;
