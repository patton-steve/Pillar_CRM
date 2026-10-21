-- Pillar master list for ClientType. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultClientType
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultClientType PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultClientType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultClientType_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultClientType_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultClientType_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'ClientType') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultClientType_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultClientType_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultClientType_Code UNIQUE (Code),
    CONSTRAINT CK_DefaultClientType_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT FK_DefaultClientType_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultClientType_IsDefault ON lkp.DefaultClientType (IsDefault) WHERE IsDefault = 1;
