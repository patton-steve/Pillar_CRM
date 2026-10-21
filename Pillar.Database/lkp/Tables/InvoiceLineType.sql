-- Tenant working list for InvoiceLineType: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.InvoiceLineType
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceLineType PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_InvoiceLineType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_InvoiceLineType_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_InvoiceLineType_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_InvoiceLineType_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_InvoiceLineType_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'InvoiceLineType') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceLineType_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_InvoiceLineType_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_InvoiceLineType_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_InvoiceLineType_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT CK_InvoiceLineType_NoCustom CHECK (IsCustom = 0 AND IsLocked = 1),  -- Pillar-defined list
    CONSTRAINT UQ_InvoiceLineType_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_InvoiceLineType_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_InvoiceLineType_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultInvoiceLineType (Id),
    CONSTRAINT FK_InvoiceLineType_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_InvoiceLineType_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceLineType_Tenant_Default
    ON lkp.InvoiceLineType (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceLineType_Tenant_IsDefault
    ON lkp.InvoiceLineType (TenantId) WHERE IsDefault = 1;
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceLineType_Tenant_SystemCode
    ON lkp.InvoiceLineType (TenantId, SystemCode);
