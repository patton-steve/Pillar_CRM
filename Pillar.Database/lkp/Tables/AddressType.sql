-- Tenant working list for AddressType: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.AddressType
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AddressType PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_AddressType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_AddressType_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_AddressType_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_AddressType_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_AddressType_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'AddressType') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_AddressType_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_AddressType_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_AddressType_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_AddressType_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_AddressType_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_AddressType_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultAddressType (Id),
    CONSTRAINT FK_AddressType_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_AddressType_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_AddressType_Tenant_Default
    ON lkp.AddressType (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_AddressType_Tenant_IsDefault
    ON lkp.AddressType (TenantId) WHERE IsDefault = 1;
