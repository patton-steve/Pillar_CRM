-- Where and how clients pay a tenant: the "Remit to" block and payment instructions on an invoice.
-- A tenant can keep several (e.g. a lockbox for one client group); exactly one should be IsDefault.
-- Billing profiles may name one; issue snapshots profile -> tenant default onto ar.Invoice.RemitProfileId.
-- With none at all, invoices fall back to the admin.TenantBranding address.
CREATE TABLE admin.RemitProfile
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RemitProfile PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    Code                NVARCHAR(20)    NOT NULL,
    Name                NVARCHAR(100)   NOT NULL,
    PayableTo           NVARCHAR(200)   NOT NULL,  -- "Make checks payable to"
    AddressLine1        NVARCHAR(200)   NULL,
    AddressLine2        NVARCHAR(200)   NULL,
    City                NVARCHAR(100)   NULL,
    Region              NVARCHAR(100)   NULL,
    PostalCode          NVARCHAR(20)    NULL,
    CountryCode         CHAR(2)         NOT NULL CONSTRAINT DF_RemitProfile_CountryCode DEFAULT ('US'),
    Email               NVARCHAR(254)   NULL,      -- remittance advice / AR contact
    Phone               NVARCHAR(30)    NULL,
    PaymentInstructions NVARCHAR(1000)  NULL,      -- free text that prints as-is (ACH/wire details, pay link). Printed, so not secret.
    IsDefault           BIT             NOT NULL CONSTRAINT DF_RemitProfile_IsDefault DEFAULT (0),
    IsActive            BIT             NOT NULL CONSTRAINT DF_RemitProfile_IsActive DEFAULT (1),
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_RemitProfile_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_RemitProfile_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_RemitProfile_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_RemitProfile_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_RemitProfile_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_RemitProfile_Tenant_IsDefault ON admin.RemitProfile (TenantId) WHERE IsDefault = 1;
