-- A tenant's override of a setting. No row = SettingDefinition.DefaultValue.
-- Write through admin.usp_Setting_Set, which enforces Visibility and DataType.
CREATE TABLE admin.TenantSetting
(
    TenantId        INT             NOT NULL,
    SettingKey      VARCHAR(100)    NOT NULL,
    Value           NVARCHAR(400)   NULL,
    ModifiedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantSetting_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedBy      INT             NULL CONSTRAINT DF_TenantSetting_ModifiedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT PK_TenantSetting PRIMARY KEY CLUSTERED (TenantId, SettingKey),
    CONSTRAINT FK_TenantSetting_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_TenantSetting_Setting FOREIGN KEY (SettingKey) REFERENCES admin.SettingDefinition (SettingKey)
);
