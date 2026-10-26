-- Each time Pillar support signed in as someone in a tenant ("Log in as" in the back office). Started by
-- sec.usp_Impersonation_Start under a live sec.SupportAccessGrant and ended by sec.usp_Impersonation_End, or by the tenant
-- revoking the grant. Every change made during it carries its Id in admin.AuditLog.ImpersonationSessionId, and the start and
-- end are themselves audit log rows, so the tenant sees them in Settings > Audit log.
-- PlatformAdminUserId is the Pillar admin's own login, which lives in Pillar's tenant (PlatformAdminTenantId), so there is no FK.
CREATE TABLE sec.ImpersonationSession
(
    Id                      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImpersonationSession PRIMARY KEY CLUSTERED,
    TenantId                INT             NOT NULL,
    AsUserId                INT             NOT NULL,
    GrantId                 INT             NOT NULL,
    PlatformAdminUserId     INT             NOT NULL,
    PlatformAdminTenantId   INT             NULL,
    PlatformAdminName       NVARCHAR(200)   NULL,      -- snapshot for the tenant's audit log
    Reason                  NVARCHAR(500)   NOT NULL,
    StartedAt               DATETIME2(0)    NOT NULL CONSTRAINT DF_ImpersonationSession_StartedAt DEFAULT (SYSUTCDATETIME()),
    EndedAt                 DATETIME2(0)    NULL,
    EndReason               VARCHAR(10)     NULL,      -- SIGNOUT, REVOKED, EXPIRED
    IpAddress               VARCHAR(45)     NULL,
    CONSTRAINT UQ_ImpersonationSession_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT FK_ImpersonationSession_AsUser FOREIGN KEY (TenantId, AsUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_ImpersonationSession_Grant FOREIGN KEY (TenantId, GrantId) REFERENCES sec.SupportAccessGrant (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_ImpersonationSession_Open ON sec.ImpersonationSession (TenantId, GrantId) WHERE EndedAt IS NULL;
