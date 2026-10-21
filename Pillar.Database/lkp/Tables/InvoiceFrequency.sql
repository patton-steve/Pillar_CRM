-- Tenant working list for InvoiceFrequency: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.InvoiceFrequency
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceFrequency PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_InvoiceFrequency_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_InvoiceFrequency_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_InvoiceFrequency_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_InvoiceFrequency_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_InvoiceFrequency_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'InvoiceFrequency') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceFrequency_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_InvoiceFrequency_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_InvoiceFrequency_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_InvoiceFrequency_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT UQ_InvoiceFrequency_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_InvoiceFrequency_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_InvoiceFrequency_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultInvoiceFrequency (Id),
    CONSTRAINT FK_InvoiceFrequency_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_InvoiceFrequency_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceFrequency_Tenant_Default
    ON lkp.InvoiceFrequency (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceFrequency_Tenant_IsDefault
    ON lkp.InvoiceFrequency (TenantId) WHERE IsDefault = 1;
