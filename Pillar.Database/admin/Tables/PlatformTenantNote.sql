-- Pillar's private notes on a tenant (back office > tenant > Notes). Pillar only: outside RLS, reached through
-- admin.usp_PlatformTenantNote_Save and admin.usp_PlatformTenant_Get.
CREATE TABLE admin.PlatformTenantNote
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformTenantNote PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Body            NVARCHAR(4000)  NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformTenantNote_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_PlatformTenantNote_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    DeletedAt       DATETIME2(0)    NULL,
    CONSTRAINT FK_PlatformTenantNote_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_PlatformTenantNote_Tenant ON admin.PlatformTenantNote (TenantId, Id DESC) WHERE DeletedAt IS NULL;
