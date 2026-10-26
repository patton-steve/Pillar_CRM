-- Pillar's own audit trail: every back-office action (approve, decline, status, plan and fee override changes with their
-- reason, payments marked paid, support sign-ins, user edits across a tenant). Append-only (admin.trg_PlatformAudit_AppendOnly).
-- Pillar only: outside RLS, read through admin.usp_PlatformAudit_List; never grant the API SELECT on it. Written by
-- admin.usp_PlatformAudit_Write. Changes made inside a tenant also land in that tenant's admin.AuditLog.
CREATE TABLE admin.PlatformAudit
(
    Id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformAudit PRIMARY KEY CLUSTERED,
    OccurredAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformAudit_OccurredAt DEFAULT (SYSUTCDATETIME()),
    ActorUserId     INT             NULL CONSTRAINT DF_PlatformAudit_ActorUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    TenantId        INT             NULL,          -- the tenant acted on
    Action          VARCHAR(30)     NOT NULL,      -- APPROVE, DECLINE, SET_STATUS, SET_PLAN, SET_OVERRIDE, MARK_PAID, SUPPORT_SIGNIN, ...
    EntityType      VARCHAR(30)     NULL,
    EntityKey       NVARCHAR(100)   NULL,
    Summary         NVARCHAR(400)   NULL,
    Reason          NVARCHAR(500)   NULL,
    ChangeJson      NVARCHAR(MAX)   NULL,
    IpAddress       VARCHAR(45)     NULL CONSTRAINT DF_PlatformAudit_IpAddress DEFAULT (CONVERT(VARCHAR(45), SESSION_CONTEXT(N'ClientIp'))),
    CONSTRAINT CK_PlatformAudit_ChangeJson CHECK (ChangeJson IS NULL OR ISJSON(ChangeJson) = 1),
    CONSTRAINT FK_PlatformAudit_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_PlatformAudit_Tenant ON admin.PlatformAudit (TenantId, Id DESC) WHERE TenantId IS NOT NULL;
