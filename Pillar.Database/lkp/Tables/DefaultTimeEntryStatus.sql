-- Pillar master list for TimeEntryStatus. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultTimeEntryStatus
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultTimeEntryStatus PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultTimeEntryStatus_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultTimeEntryStatus_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultTimeEntryStatus_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultTimeEntryStatus_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'TimeEntryStatus') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultTimeEntryStatus_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultTimeEntryStatus_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultTimeEntryStatus_Code UNIQUE (Code),
    CONSTRAINT CK_DefaultTimeEntryStatus_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT CK_DefaultTimeEntryStatus_NoCustom CHECK (IsLocked = 1),  -- Pillar-defined list
    CONSTRAINT FK_DefaultTimeEntryStatus_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultTimeEntryStatus_IsDefault ON lkp.DefaultTimeEntryStatus (IsDefault) WHERE IsDefault = 1;
