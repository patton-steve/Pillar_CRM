-- Shared address store. Linked to clients through crm.ClientAddress; Contact, RemitProfile and Vendor link the same way later.
CREATE TABLE crm.Address
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Address PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Line1           NVARCHAR(200)   NOT NULL,
    Line2           NVARCHAR(200)   NULL,
    Line3           NVARCHAR(200)   NULL,
    City            NVARCHAR(100)   NOT NULL,
    Region          NVARCHAR(100)   NULL,      -- state / province
    PostalCode      NVARCHAR(20)    NULL,
    CountryCode     CHAR(2)         NOT NULL CONSTRAINT DF_Address_CountryCode DEFAULT ('US'),
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Address_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Address_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_Address_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT FK_Address_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
