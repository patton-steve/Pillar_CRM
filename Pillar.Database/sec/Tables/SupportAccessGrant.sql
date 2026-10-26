-- The tenant's permission for Pillar support to sign in as one of its people (Settings > Security, Steve 2026-10-22:
-- "Log in as" only with the tenant's permission). Granted and revoked by someone with settings.security (Owner and Admin by
-- default) through sec.usp_SupportAccess_Grant / _Revoke. A grant is live while RevokedAt IS NULL and ExpiresAt is ahead.
CREATE TABLE sec.SupportAccessGrant
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SupportAccessGrant PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    GrantedBy       INT             NOT NULL,
    GrantedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_SupportAccessGrant_GrantedAt DEFAULT (SYSUTCDATETIME()),
    ExpiresAt       DATETIME2(0)    NOT NULL,
    Note            NVARCHAR(500)   NULL,          -- e.g. "for ticket 123"
    RevokedAt       DATETIME2(0)    NULL,
    RevokedBy       INT             NULL,
    CONSTRAINT UQ_SupportAccessGrant_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_SupportAccessGrant_Expiry CHECK (ExpiresAt > GrantedAt),
    CONSTRAINT FK_SupportAccessGrant_GrantedBy FOREIGN KEY (TenantId, GrantedBy) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_SupportAccessGrant_Live ON sec.SupportAccessGrant (TenantId, ExpiresAt) WHERE RevokedAt IS NULL;
