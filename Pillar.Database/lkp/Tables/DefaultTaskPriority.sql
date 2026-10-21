-- Pillar master list for TaskPriority. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultTaskPriority
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultTaskPriority PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultTaskPriority_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultTaskPriority_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultTaskPriority_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultTaskPriority_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'TaskPriority') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultTaskPriority_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultTaskPriority_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultTaskPriority_Code UNIQUE (Code),
    CONSTRAINT FK_DefaultTaskPriority_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultTaskPriority_IsDefault ON lkp.DefaultTaskPriority (IsDefault) WHERE IsDefault = 1;
