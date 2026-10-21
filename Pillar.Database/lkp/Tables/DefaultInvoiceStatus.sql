-- Pillar master list for InvoiceStatus. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.DefaultInvoiceStatus
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DefaultInvoiceStatus PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultInvoiceStatus_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_DefaultInvoiceStatus_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_DefaultInvoiceStatus_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultInvoiceStatus_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'InvoiceStatus') PERSISTED NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_DefaultInvoiceStatus_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_DefaultInvoiceStatus_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_DefaultInvoiceStatus_Code UNIQUE (Code),
    CONSTRAINT CK_DefaultInvoiceStatus_SystemCodeRequired CHECK (SystemCode IS NOT NULL),
    CONSTRAINT CK_DefaultInvoiceStatus_NoCustom CHECK (IsLocked = 1),  -- Pillar-defined list
    CONSTRAINT FK_DefaultInvoiceStatus_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DefaultInvoiceStatus_IsDefault ON lkp.DefaultInvoiceStatus (IsDefault) WHERE IsDefault = 1;
