-- The Today layout an admin publishes for a role (Steve 2026-10-22). LayoutJson is the same shape as the person's own
-- layout in admin.UserPreference 'ui.todayLayout'; the API validates it against the widget catalog it owns.
-- Which layout a person sees (admin.usp_TodayLayout_Get): their own, else their role's published layout, else Pillar's
-- built-in default for the role's BaseRoleCode (kept in API code).
CREATE TABLE admin.RoleDashboardLayout
(
    TenantId        INT             NOT NULL,
    RoleId          INT             NOT NULL,
    LayoutJson      NVARCHAR(MAX)   NOT NULL,
    PublishedAt     DATETIME2(0)    NOT NULL CONSTRAINT DF_RoleDashboardLayout_PublishedAt DEFAULT (SYSUTCDATETIME()),
    PublishedBy     INT             NULL CONSTRAINT DF_RoleDashboardLayout_PublishedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT PK_RoleDashboardLayout PRIMARY KEY CLUSTERED (TenantId, RoleId),
    CONSTRAINT CK_RoleDashboardLayout_Json CHECK (ISJSON(LayoutJson) = 1 AND LEN(LayoutJson) <= 20000),
    CONSTRAINT FK_RoleDashboardLayout_Role FOREIGN KEY (TenantId, RoleId) REFERENCES sec.Role (TenantId, Id),
    CONSTRAINT FK_RoleDashboardLayout_PublishedBy FOREIGN KEY (TenantId, PublishedBy) REFERENCES sec.AppUser (TenantId, Id)
);
