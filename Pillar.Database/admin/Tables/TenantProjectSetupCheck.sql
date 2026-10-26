-- A tenant's level for one project setup check (Settings > Projects). No row = the check's DefaultLevel.
-- Written by admin.usp_ProjectSetupCheck_Set.
CREATE TABLE admin.TenantProjectSetupCheck
(
    TenantId        INT             NOT NULL,
    CheckCode       VARCHAR(30)     NOT NULL,
    Level           VARCHAR(5)      NOT NULL,
    ModifiedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantProjectSetupCheck_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedBy      INT             NULL CONSTRAINT DF_TenantProjectSetupCheck_ModifiedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT PK_TenantProjectSetupCheck PRIMARY KEY CLUSTERED (TenantId, CheckCode),
    CONSTRAINT CK_TenantProjectSetupCheck_Level CHECK (Level = 'OFF' OR Level = 'WARN' OR Level = 'BLOCK'),
    CONSTRAINT FK_TenantProjectSetupCheck_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_TenantProjectSetupCheck_Check FOREIGN KEY (CheckCode) REFERENCES admin.ProjectSetupCheck (Code)
);
