-- Email templates a tenant manages in Settings > Email templates. A billing profile can pick an INVOICE template
-- (crm.ClientBillingProfile.InvoiceEmailTemplateId); otherwise the tenant's default for the type is used
-- (admin.fn_EmailTemplateFor). Subject and BodyHtml take merge tokens the API fills when sending:
--   {ClientName} {InvoiceNumber} {InvoiceDate} {AmountDue} {DueDate} {TenantName}
-- Each tenant gets one default INVOICE template (admin.usp_SeedTenantEmailTemplates). Write through admin.usp_EmailTemplate_Save.
CREATE TABLE admin.EmailTemplate
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmailTemplate PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    TemplateType    VARCHAR(20)     NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    Subject         NVARCHAR(300)   NOT NULL,
    BodyHtml        NVARCHAR(MAX)   NOT NULL,
    IsDefault       BIT             NOT NULL CONSTRAINT DF_EmailTemplate_IsDefault DEFAULT (0),
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_EmailTemplate_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_EmailTemplate_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_EmailTemplate_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_EmailTemplate_Type CHECK (
        TemplateType = 'INVOICE' OR TemplateType = 'CREDIT_MEMO' OR TemplateType = 'STATEMENT' OR TemplateType = 'REMINDER'),
    CONSTRAINT CK_EmailTemplate_DefaultNotDeleted CHECK (IsDefault = 0 OR DeletedAt IS NULL),
    CONSTRAINT FK_EmailTemplate_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_EmailTemplate_Default ON admin.EmailTemplate (TenantId, TemplateType) WHERE IsDefault = 1;
