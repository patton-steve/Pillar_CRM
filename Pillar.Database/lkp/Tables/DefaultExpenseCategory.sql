-- Pillar master list for ExpenseCategory. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultExpenseCategory
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultExpenseCategory PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultExpenseCategory_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultExpenseCategory_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultExpenseCategory_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultExpenseCategory_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'ExpenseCategory') PERSISTED NOT NULL,
    UnitName        NVARCHAR(20) NULL,
    UnitRate        DECIMAL(19,4) NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultExpenseCategory_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultExpenseCategory_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultExpenseCategory_Code UNIQUE (Code),
    CONSTRAINT CK_DefaultExpenseCategory_UnitRate CHECK (UnitRate IS NULL OR UnitRate >= 0),
    CONSTRAINT FK_DefaultExpenseCategory_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultExpenseCategory_IsDefault ON lkp.DefaultExpenseCategory (IsDefault) WHERE IsDefault = 1;
