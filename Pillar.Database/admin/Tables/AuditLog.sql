-- Every admin change in a tenant, viewable and filterable in Settings > Audit log (Steve 2026-10-21). Append-only:
-- written only through admin.usp_Audit_Write (the admin procs call it; the API calls it for admin writes it makes itself,
-- such as lookup list edits), and admin.trg_AuditLog_AppendOnly refuses updates and deletes.
--   Area        the settings page (permission suffix): company, users, lists, time, projects, invoicing, email, branding, import,
--               integrations, pilo, security, custom_fields, notifications, billing
--   EntityType  what changed (SETTING, ROLE, ROLE_PERMISSION, USER, CUSTOM_FIELD, EMAIL_TEMPLATE, ...); EntityKey its id or key
--   Action      CREATE, UPDATE, DELETE, GRANT, REVOKE, ENABLE, DISABLE
--   ChangeJson  [{"field":"Value","from":"0","to":"1"}] (null for a side that didn't exist); Summary is one readable line
--   IpAddress   SESSION_CONTEXT ClientIp, set by the API on each connection
--   ImpersonationSessionId  set when Pillar support made the change while signed in as someone (SESSION_CONTEXT
--               ImpersonationSessionId, set by the API on support connections; sec.ImpersonationSession says who)
-- Area also has support (Pillar support sign-ins) and billing.
CREATE TABLE admin.AuditLog
(
    Id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    OccurredAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_AuditLog_OccurredAt DEFAULT (SYSUTCDATETIME()),
    ActorUserId     INT             NULL CONSTRAINT DF_AuditLog_ActorUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    Area            VARCHAR(30)     NOT NULL,
    EntityType      VARCHAR(30)     NOT NULL,
    EntityKey       NVARCHAR(100)   NULL,
    Action          VARCHAR(10)     NOT NULL,
    Summary         NVARCHAR(400)   NULL,
    ChangeJson      NVARCHAR(MAX)   NULL,
    IpAddress       VARCHAR(45)     NULL CONSTRAINT DF_AuditLog_IpAddress DEFAULT (CONVERT(VARCHAR(45), SESSION_CONTEXT(N'ClientIp'))),
    ImpersonationSessionId INT      NULL CONSTRAINT DF_AuditLog_ImpersonationSessionId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'ImpersonationSessionId'))),   -- handoff 22: appended
    CONSTRAINT CK_AuditLog_Action CHECK (Action = 'CREATE' OR Action = 'UPDATE' OR Action = 'DELETE' OR Action = 'GRANT'
        OR Action = 'REVOKE' OR Action = 'ENABLE' OR Action = 'DISABLE'),
    CONSTRAINT CK_AuditLog_ChangeJson CHECK (ChangeJson IS NULL OR ISJSON(ChangeJson) = 1),
    CONSTRAINT FK_AuditLog_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_AuditLog_Tenant ON admin.AuditLog (TenantId, Id DESC) INCLUDE (Area, ActorUserId, EntityType);
