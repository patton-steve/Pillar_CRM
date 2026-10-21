-- Starting values a tenant type gets at sign-up, where they differ from SettingDefinition.DefaultValue.
CREATE TABLE admin.TenantTypeSettingDefault
(
    TenantTypeId    INT             NOT NULL,
    SettingKey      VARCHAR(100)    NOT NULL,
    Value           NVARCHAR(400)   NULL,
    CONSTRAINT PK_TenantTypeSettingDefault PRIMARY KEY CLUSTERED (TenantTypeId, SettingKey),
    CONSTRAINT FK_TenantTypeSettingDefault_TenantType FOREIGN KEY (TenantTypeId) REFERENCES admin.TenantType (Id),
    CONSTRAINT FK_TenantTypeSettingDefault_Setting FOREIGN KEY (SettingKey) REFERENCES admin.SettingDefinition (SettingKey)
);
