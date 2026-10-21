-- A user's override of a setting whose definition has AllowUserOverride = 1,
-- e.g. TimeEntry.RequireApproval = 0 for the owner so their own time auto-approves.
CREATE TABLE admin.UserSetting
(
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    SettingKey      VARCHAR(100)    NOT NULL,
    Value           NVARCHAR(400)   NULL,
    ModifiedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_UserSetting_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedBy      INT             NULL CONSTRAINT DF_UserSetting_ModifiedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT PK_UserSetting PRIMARY KEY CLUSTERED (TenantId, AppUserId, SettingKey),
    CONSTRAINT FK_UserSetting_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_UserSetting_Setting FOREIGN KEY (SettingKey) REFERENCES admin.SettingDefinition (SettingKey),
    CONSTRAINT FK_UserSetting_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
