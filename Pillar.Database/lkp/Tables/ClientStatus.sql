-- Tenant working list for ClientStatus: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.ClientStatus
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientStatus PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_ClientStatus_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_ClientStatus_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_ClientStatus_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_ClientStatus_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_ClientStatus_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'ClientStatus') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientStatus_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ClientStatus_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ClientStatus_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_ClientStatus_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT UQ_ClientStatus_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_ClientStatus_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_ClientStatus_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultClientStatus (Id),
    CONSTRAINT FK_ClientStatus_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_ClientStatus_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_ClientStatus_Tenant_Default
    ON lkp.ClientStatus (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_ClientStatus_Tenant_IsDefault
    ON lkp.ClientStatus (TenantId) WHERE IsDefault = 1;
