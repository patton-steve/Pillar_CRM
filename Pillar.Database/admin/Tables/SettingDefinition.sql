-- Pillar-owned catalog of every configurable setting.
-- Visibility: TENANT_EDIT  = tenant sees and changes it (e.g. TimeEntry.RequireApproval)
--             TENANT_READ  = tenant sees it, only Pillar changes it (e.g. user limit)
--             PLATFORM_ONLY = hidden from the tenant (fee overrides, feature flags)
-- AllowUserOverride: the value can also be set per user (user value beats tenant value).
-- PermissionCode: the settings-page permission needed to change the tenant value (admin.usp_Setting_Set); set by the
-- post-deploy from Category. NULL = Pillar only. A person may always set their own per-user override.
CREATE TABLE admin.SettingDefinition
(
    SettingKey          VARCHAR(100)    NOT NULL CONSTRAINT PK_SettingDefinition PRIMARY KEY CLUSTERED,
    Category            NVARCHAR(50)    NOT NULL,
    DisplayName         NVARCHAR(100)   NOT NULL,
    Description         NVARCHAR(400)   NULL,
    DataType            VARCHAR(10)     NOT NULL,
    DefaultValue        NVARCHAR(400)   NULL,
    AllowedValues       NVARCHAR(1000)  NULL,      -- JSON array, e.g. ["0","6","15","30"]; NULL = any value of DataType
    Visibility          VARCHAR(15)     NOT NULL,
    AllowUserOverride   BIT             NOT NULL CONSTRAINT DF_SettingDefinition_AllowUserOverride DEFAULT (0),
    SortOrder           INT             NOT NULL CONSTRAINT DF_SettingDefinition_SortOrder DEFAULT (0),
    PermissionCode      VARCHAR(50)     NULL,          -- appended in handoff 21
    CONSTRAINT CK_SettingDefinition_DataType CHECK (DataType IN ('BIT', 'INT', 'DECIMAL', 'STRING', 'DATE')),
    CONSTRAINT CK_SettingDefinition_Visibility CHECK (Visibility IN ('TENANT_EDIT', 'TENANT_READ', 'PLATFORM_ONLY')),
    CONSTRAINT CK_SettingDefinition_AllowedValues CHECK (AllowedValues IS NULL OR ISJSON(AllowedValues) = 1),
    -- only tenant-editable settings make sense per user
    CONSTRAINT CK_SettingDefinition_UserOverride CHECK (AllowUserOverride = 0 OR Visibility = 'TENANT_EDIT'),
    CONSTRAINT FK_SettingDefinition_Permission FOREIGN KEY (PermissionCode) REFERENCES sec.Permission (Code)
);
