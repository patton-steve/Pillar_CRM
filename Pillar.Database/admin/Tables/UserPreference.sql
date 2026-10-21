-- Free-form per-user UI state the app owns (theme, accent, nav order, dashboard layout...). Unlike admin.UserSetting these
-- keys are not in admin.SettingDefinition and never change business rules. Value is JSON text (a JSON string, number,
-- boolean, array or object); the API validates its shape per key. Write through admin.usp_UserPreference_Set.
CREATE TABLE admin.UserPreference
(
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    PrefKey         VARCHAR(100)    NOT NULL,      -- e.g. ui.theme, ui.navOrder, dashboard.layout, timer.followMe
    Value           NVARCHAR(MAX)   NOT NULL,
    ModifiedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_UserPreference_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserPreference PRIMARY KEY CLUSTERED (TenantId, AppUserId, PrefKey),
    CONSTRAINT CK_UserPreference_Key CHECK (PrefKey LIKE '[a-z]%.[a-zA-Z]%'),
    CONSTRAINT CK_UserPreference_Size CHECK (LEN(Value) <= 20000),
    CONSTRAINT FK_UserPreference_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
