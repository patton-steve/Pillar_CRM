-- Pillar master list for TimesheetStatus. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultTimesheetStatus
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultTimesheetStatus PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultTimesheetStatus_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultTimesheetStatus_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultTimesheetStatus_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultTimesheetStatus_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'TimesheetStatus') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultTimesheetStatus_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultTimesheetStatus_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultTimesheetStatus_Code UNIQUE (Code),
    CONSTRAINT CK_DefaultTimesheetStatus_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT CK_DefaultTimesheetStatus_NoCustom CHECK (IsLocked = 1),  -- Pillar-defined list
    CONSTRAINT FK_DefaultTimesheetStatus_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultTimesheetStatus_IsDefault ON lkp.DefaultTimesheetStatus (IsDefault) WHERE IsDefault = 1;
