-- A client's addresses. Billing profiles pick one of these, which guarantees the address belongs to that client.
CREATE TABLE crm.ClientAddress
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientAddress PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    ClientId        INT             NOT NULL,
    AddressId       INT             NOT NULL,
    AddressTypeId   INT             NOT NULL,
    Label           NVARCHAR(100)   NULL,      -- e.g. "AWS AP Lockbox"
    IsPrimary       BIT             NOT NULL CONSTRAINT DF_ClientAddress_IsPrimary DEFAULT (0),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientAddress_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ClientAddress_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ClientAddress_Client_Address UNIQUE (TenantId, ClientId, AddressId),
    CONSTRAINT FK_ClientAddress_Client FOREIGN KEY (TenantId, ClientId) REFERENCES crm.Client (TenantId, Id),
    CONSTRAINT FK_ClientAddress_Address FOREIGN KEY (TenantId, AddressId) REFERENCES crm.Address (TenantId, Id),
    CONSTRAINT FK_ClientAddress_AddressType FOREIGN KEY (TenantId, AddressTypeId) REFERENCES lkp.AddressType (TenantId, Id)
);
GO
-- At most one primary address per type per client.
CREATE UNIQUE NONCLUSTERED INDEX UX_ClientAddress_Primary
    ON crm.ClientAddress (TenantId, ClientId, AddressTypeId) WHERE IsPrimary = 1;
