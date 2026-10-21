-- Refresh tokens for the API's short-lived JWTs, stored as SHA-256 hashes. Each use rotates the token within its family;
-- presenting an already-rotated token revokes the whole family (stolen-token detection). Outside RLS (used before the
-- tenant is known); reach it only through the sec.usp_Auth_* procs.
CREATE TABLE sec.RefreshToken
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RefreshToken PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    AppUserId           INT             NOT NULL,
    FamilyId            UNIQUEIDENTIFIER NOT NULL,     -- one per sign-in; shared by its rotations
    TokenHash           BINARY(32)      NOT NULL,
    IssuedAt            DATETIME2(0)    NOT NULL CONSTRAINT DF_RefreshToken_IssuedAt DEFAULT (SYSUTCDATETIME()),
    ExpiresAt           DATETIME2(0)    NOT NULL,
    RevokedAt           DATETIME2(0)    NULL,
    RevokedReason       VARCHAR(20)     NULL,          -- ROTATED, LOGOUT, REUSE, PASSWORD_RESET, DISABLED
    ReplacedByTokenId   INT             NULL,
    IpAddress           VARCHAR(45)     NULL,
    UserAgent           NVARCHAR(400)   NULL,
    CONSTRAINT UQ_RefreshToken_Hash UNIQUE (TokenHash),
    CONSTRAINT FK_RefreshToken_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_RefreshToken_ReplacedBy FOREIGN KEY (ReplacedByTokenId) REFERENCES sec.RefreshToken (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_RefreshToken_User ON sec.RefreshToken (AppUserId) WHERE RevokedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_RefreshToken_Family ON sec.RefreshToken (FamilyId);
