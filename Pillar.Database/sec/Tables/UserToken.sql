-- One-time links sent by email: INVITE (set your password), RESET (forgot password) and VERIFY (confirm the sign-up email, handoff 22). The API emails the raw token and
-- stores only its SHA-256 hash. Outside RLS (redeemed before sign-in); reach it only through the sec.usp_Auth_* / usp_User_* procs.
CREATE TABLE sec.UserToken
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UserToken PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    Purpose         VARCHAR(10)     NOT NULL,
    TokenHash       BINARY(32)      NOT NULL,
    ExpiresAt       DATETIME2(0)    NOT NULL,
    UsedAt          DATETIME2(0)    NULL,
    RevokedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_UserToken_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_UserToken_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT UQ_UserToken_Hash UNIQUE (TokenHash),
    CONSTRAINT CK_UserToken_Purpose CHECK (Purpose = 'INVITE' OR Purpose = 'RESET' OR Purpose = 'VERIFY'),
    CONSTRAINT FK_UserToken_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_UserToken_User ON sec.UserToken (AppUserId, Purpose) WHERE UsedAt IS NULL AND RevokedAt IS NULL;
