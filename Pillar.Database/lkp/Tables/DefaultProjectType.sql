-- Pillar master list for ProjectType. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultProjectType
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultProjectType PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultProjectType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultProjectType_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultProjectType_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultProjectType_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'ProjectType') PERSISTED NOT NULL,
    KeyPrefix       VARCHAR(10) NOT NULL,
    DefaultBillingTypeId INT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultProjectType_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultProjectType_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultProjectType_Code UNIQUE (Code),
    CONSTRAINT CK_DefaultProjectType_KeyPrefix CHECK (LEN(KeyPrefix) >= 2 AND KeyPrefix COLLATE Latin1_General_BIN NOT LIKE '%[^A-Z0-9]%' AND LEFT(KeyPrefix, 1) COLLATE Latin1_General_BIN LIKE '[A-Z]'),
    CONSTRAINT UQ_DefaultProjectType_KeyPrefix UNIQUE (KeyPrefix),
    CONSTRAINT FK_DefaultProjectType_DefaultBillingTypeId FOREIGN KEY (DefaultBillingTypeId) REFERENCES lkp.DefaultBillingType (Id),
    CONSTRAINT FK_DefaultProjectType_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultProjectType_IsDefault ON lkp.DefaultProjectType (IsDefault) WHERE IsDefault = 1;
