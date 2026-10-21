-- Links a user to an outside identity provider. Empty in phase 1; Microsoft Entra External ID plugs in here later
-- (Provider = 'ENTRA', Subject = the token's oid/sub). Outside RLS, like the other sign-in tables.
CREATE TABLE sec.ExternalLogin
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExternalLogin PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    Provider        VARCHAR(20)     NOT NULL,
    Subject         NVARCHAR(200)   NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ExternalLogin_CreatedAt DEFAULT (SYSUTCDATETIME()),
    LastUsedAt      DATETIME2(0)    NULL,
    CONSTRAINT UQ_ExternalLogin_Provider_Subject UNIQUE (Provider, Subject),
    CONSTRAINT FK_ExternalLogin_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
