-- Tenant working list for InvoiceStatus: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.InvoiceStatus
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceStatus PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_InvoiceStatus_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_InvoiceStatus_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_InvoiceStatus_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_InvoiceStatus_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_InvoiceStatus_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'InvoiceStatus') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceStatus_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_InvoiceStatus_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_InvoiceStatus_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_InvoiceStatus_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT CK_InvoiceStatus_NoCustom CHECK (IsCustom = 0 AND IsLocked = 1),  -- Pillar-defined list
    CONSTRAINT UQ_InvoiceStatus_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_InvoiceStatus_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_InvoiceStatus_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultInvoiceStatus (Id),
    CONSTRAINT FK_InvoiceStatus_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_InvoiceStatus_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceStatus_Tenant_Default
    ON lkp.InvoiceStatus (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceStatus_Tenant_IsDefault
    ON lkp.InvoiceStatus (TenantId) WHERE IsDefault = 1;
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceStatus_Tenant_SystemCode
    ON lkp.InvoiceStatus (TenantId, SystemCode);
