-- How a tenant appears on invoices and statements: company block, accent color and logo. One row per tenant, created on first save.
-- The logo is stored in the row so SSRS can render it as a database image (admin.usp_TenantLogo).
-- Write the logo only through admin.usp_TenantBranding_SetLogo, which checks the file signature; text columns are edited directly.
CREATE TABLE admin.TenantBranding
(
    TenantId        INT             NOT NULL CONSTRAINT PK_TenantBranding PRIMARY KEY CLUSTERED,
    CompanyName     NVARCHAR(200)   NULL,      -- NULL = admin.Tenant.Name
    AddressLine1    NVARCHAR(200)   NULL,
    AddressLine2    NVARCHAR(200)   NULL,
    City            NVARCHAR(100)   NULL,
    Region          NVARCHAR(100)   NULL,
    PostalCode      NVARCHAR(20)    NULL,
    CountryCode     CHAR(2)         NOT NULL CONSTRAINT DF_TenantBranding_CountryCode DEFAULT ('US'),
    Phone           NVARCHAR(30)    NULL,
    Email           NVARCHAR(254)   NULL,
    Website         NVARCHAR(200)   NULL,
    TaxId           NVARCHAR(30)    NULL,      -- prints only when the layout's ShowTaxId = 1
    AccentColor     CHAR(7)         NULL,      -- #RRGGBB for headings and rules; NULL = report default
    LogoImage       VARBINARY(MAX)  NULL,
    LogoMimeType    VARCHAR(20)     NULL,
    LogoFileName    NVARCHAR(260)   NULL,
    LogoBytes       AS DATALENGTH(LogoImage),
    LogoUpdatedAt   DATETIME2(0)    NULL,
    LogoUpdatedBy   INT             NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantBranding_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_TenantBranding_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    -- 512 KB is plenty for a print logo and keeps report renders fast
    CONSTRAINT CK_TenantBranding_LogoSize CHECK (LogoImage IS NULL OR DATALENGTH(LogoImage) <= 524288),
    CONSTRAINT CK_TenantBranding_LogoMimeType CHECK (
        (LogoImage IS NULL AND LogoMimeType IS NULL)
        OR (LogoImage IS NOT NULL AND LogoMimeType IN ('image/png', 'image/jpeg'))),
    CONSTRAINT CK_TenantBranding_AccentColor CHECK (AccentColor IS NULL OR AccentColor LIKE '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]'),
    CONSTRAINT FK_TenantBranding_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
