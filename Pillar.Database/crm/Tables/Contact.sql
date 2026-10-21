-- People behind a client. Each contact belongs to exactly one client.
CREATE TABLE crm.Contact
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Contact PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Contact_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    ClientId        INT             NOT NULL,
    FirstName       NVARCHAR(100)   NOT NULL,
    LastName        NVARCHAR(100)   NULL,
    DisplayName     AS CONCAT_WS(N' ', FirstName, LastName),
    Title           NVARCHAR(100)   NULL,
    Email           NVARCHAR(254)   NULL,
    Phone           NVARCHAR(30)    NULL,
    Mobile          NVARCHAR(30)    NULL,
    ContactRoleId   INT             NULL,
    IsPrimary       BIT             NOT NULL CONSTRAINT DF_Contact_IsPrimary DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_Contact_IsActive DEFAULT (1),
    Notes           NVARCHAR(MAX)   NULL,
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Contact_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Contact_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_Contact_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_Contact_Tenant_Id UNIQUE (TenantId, Id),
    -- lets billing tables require that a contact belongs to the same client
    CONSTRAINT UQ_Contact_Tenant_Client_Id UNIQUE (TenantId, ClientId, Id),
    CONSTRAINT FK_Contact_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    CONSTRAINT FK_Contact_ContactRole FOREIGN KEY (TenantId, ContactRoleId) REFERENCES lkp.ContactRole (TenantId, Id)
);
GO
-- One primary contact per client.
CREATE UNIQUE NONCLUSTERED INDEX UX_Contact_Primary
    ON crm.Contact (TenantId, ClientId) WHERE IsPrimary = 1 AND DeletedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_Contact_Tenant_Email ON crm.Contact (TenantId, Email) WHERE Email IS NOT NULL;
