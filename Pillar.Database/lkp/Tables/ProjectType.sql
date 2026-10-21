-- Tenant working list for ProjectType: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.ProjectType
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProjectType PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_ProjectType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_ProjectType_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_ProjectType_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_ProjectType_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_ProjectType_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'ProjectType') PERSISTED NOT NULL,
    KeyPrefix       VARCHAR(10) NOT NULL,
    DefaultBillingTypeId INT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ProjectType_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ProjectType_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ProjectType_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_ProjectType_KeyPrefix CHECK (LEN(KeyPrefix) >= 2 AND KeyPrefix COLLATE Latin1_General_BIN NOT LIKE '%[^A-Z0-9]%' AND LEFT(KeyPrefix, 1) COLLATE Latin1_General_BIN LIKE '[A-Z]'),
    CONSTRAINT UQ_ProjectType_KeyPrefix UNIQUE (TenantId, KeyPrefix),
    CONSTRAINT FK_ProjectType_DefaultBillingTypeId FOREIGN KEY (TenantId, DefaultBillingTypeId) REFERENCES lkp.BillingType (TenantId, Id),
    CONSTRAINT UQ_ProjectType_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_ProjectType_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_ProjectType_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultProjectType (Id),
    CONSTRAINT FK_ProjectType_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_ProjectType_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_ProjectType_Tenant_Default
    ON lkp.ProjectType (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_ProjectType_Tenant_IsDefault
    ON lkp.ProjectType (TenantId) WHERE IsDefault = 1;
