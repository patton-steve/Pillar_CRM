-- Login secrets for users with CanLogin = 1. Outside RLS on purpose: sign-in, refresh and password reset happen before the
-- API knows the tenant, so these rows are found by email or token. Reach it only through the sec.usp_Auth_* procs
-- (grant the API EXECUTE on them, not SELECT on this table).
-- LoginEmail and IsEnabled mirror sec.AppUser (kept in step by sec.trg_AppUser_Rules).
-- PasswordHash is bcrypt from the API; NULL until an invite is accepted. MfaSecret is encrypted by the API before it gets here.
CREATE TABLE sec.UserCredential
(
    AppUserId           INT             NOT NULL CONSTRAINT PK_UserCredential PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    LoginEmail          NVARCHAR(254)   NOT NULL,      -- normalized (lower, trimmed)
    IsEnabled           BIT             NOT NULL,      -- CanLogin = 1 and Status <> DISABLED
    PasswordHash        VARCHAR(255)    NULL,
    PasswordChangedAt   DATETIME2(0)    NULL,
    MustChangePassword  BIT             NOT NULL CONSTRAINT DF_UserCredential_MustChangePassword DEFAULT (0),
    FailedAttempts      INT             NOT NULL CONSTRAINT DF_UserCredential_FailedAttempts DEFAULT (0),
    LockedUntil         DATETIME2(0)    NULL,
    MfaSecretEncrypted  VARBINARY(512)  NULL,          -- TOTP secret
    MfaEnabledAt        DATETIME2(0)    NULL,
    RecoveryCodeHashes  NVARCHAR(MAX)   NULL,          -- JSON array of hashed one-time recovery codes
    LastLoginAt         DATETIME2(0)    NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_UserCredential_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt          DATETIME2(0)    NULL,
    CONSTRAINT UQ_UserCredential_LoginEmail UNIQUE (LoginEmail),
    CONSTRAINT CK_UserCredential_RecoveryCodes CHECK (RecoveryCodeHashes IS NULL OR ISJSON(RecoveryCodeHashes) = 1),
    CONSTRAINT FK_UserCredential_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
