-- Tenant working list for PaymentTerm: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.PaymentTerm
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PaymentTerm PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_PaymentTerm_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_PaymentTerm_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_PaymentTerm_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_PaymentTerm_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_PaymentTerm_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), 'PaymentTerm') PERSISTED NOT NULL,
    DueDays         INT NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_PaymentTerm_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_PaymentTerm_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_PaymentTerm_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_PaymentTerm_DueDays CHECK (DueDays >= 0),
    CONSTRAINT UQ_PaymentTerm_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_PaymentTerm_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_PaymentTerm_Default FOREIGN KEY (DefaultId) REFERENCES lkp.DefaultPaymentTerm (Id),
    CONSTRAINT FK_PaymentTerm_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_PaymentTerm_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_PaymentTerm_Tenant_Default
    ON lkp.PaymentTerm (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_PaymentTerm_Tenant_IsDefault
    ON lkp.PaymentTerm (TenantId) WHERE IsDefault = 1;
