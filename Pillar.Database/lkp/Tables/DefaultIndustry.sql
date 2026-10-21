-- Pillar master list for Industry. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultIndustry
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultIndustry PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultIndustry_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultIndustry_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultIndustry_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultIndustry_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'Industry') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultIndustry_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultIndustry_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultIndustry_Code UNIQUE (Code),
    CONSTRAINT FK_DefaultIndustry_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultIndustry_IsDefault ON lkp.DefaultIndustry (IsDefault) WHERE IsDefault = 1;
