-- Client identity only. Where and how a client is billed lives on crm.ClientBillingProfile (1:M).
-- IsSample (handoff 22): part of the sample company from admin.usp_SampleData_Load. admin.usp_SampleData_Remove deletes these
-- clients and everything under them (projects, tasks, time), so the UI shows a Sample chip on them.
CREATE TABLE crm.Client
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Client PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Client_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    ClientCode      NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(200)   NOT NULL,  -- company name, or display name for an individual
    FirstName       NVARCHAR(100)   NULL,      -- used when ClientType SystemCode = INDIVIDUAL
    LastName        NVARCHAR(100)   NULL,
    ClientTypeId    INT             NOT NULL,
    ClientStatusId  INT             NOT NULL,
    IndustryId      INT             NULL,
    TaxId           NVARCHAR(30)    NULL,
    Website         NVARCHAR(300)   NULL,
    Notes           NVARCHAR(MAX)   NULL,
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Client_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Client_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    AccountManagerUserId INT        NULL,      -- "my client" for notifications (new projects on it)
    IsSample        BIT             NOT NULL CONSTRAINT DF_Client_IsSample DEFAULT (0),   -- handoff 22: appended
    CONSTRAINT UQ_Client_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_Client_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Client_Tenant_Code UNIQUE (TenantId, ClientCode),
    CONSTRAINT FK_Client_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_Client_ClientType FOREIGN KEY (TenantId, ClientTypeId) REFERENCES lkp.ClientType (TenantId, Id),
    CONSTRAINT FK_Client_ClientStatus FOREIGN KEY (TenantId, ClientStatusId) REFERENCES lkp.ClientStatus (TenantId, Id),
    CONSTRAINT FK_Client_Industry FOREIGN KEY (TenantId, IndustryId) REFERENCES lkp.Industry (TenantId, Id),
    CONSTRAINT FK_Client_AccountManager FOREIGN KEY (TenantId, AccountManagerUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_Client_Tenant_Name ON crm.Client (TenantId, Name) WHERE DeletedAt IS NULL;
