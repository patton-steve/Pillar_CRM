-- A tenant's own SMTP server for emailing invoices (Settings > Email; schema ready in phase 1, sending comes later).
-- The password is never stored: PasswordSecretRef names the secret (e.g. a Key Vault secret) the API reads when sending.
-- Changing the server, account or secret clears IsVerified until the API's test send succeeds again.
-- Write through admin.usp_TenantEmailSetting_Save and usp_TenantEmailSetting_RecordTest.
CREATE TABLE admin.TenantEmailSetting
(
    TenantId            INT             NOT NULL CONSTRAINT PK_TenantEmailSetting PRIMARY KEY CLUSTERED,
    Host                NVARCHAR(255)   NOT NULL,
    Port                INT             NOT NULL,
    UseTls              BIT             NOT NULL CONSTRAINT DF_TenantEmailSetting_UseTls DEFAULT (1),
    Username            NVARCHAR(255)   NULL,
    PasswordSecretRef   NVARCHAR(200)   NULL,
    FromAddress         NVARCHAR(254)   NOT NULL,
    FromName            NVARCHAR(100)   NULL,
    ReplyTo             NVARCHAR(254)   NULL,
    IsVerified          BIT             NOT NULL CONSTRAINT DF_TenantEmailSetting_IsVerified DEFAULT (0),
    LastTestAt          DATETIME2(0)    NULL,
    LastTestError       NVARCHAR(1000)  NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantEmailSetting_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT CK_TenantEmailSetting_Port CHECK (Port >= 1 AND Port <= 65535),
    CONSTRAINT CK_TenantEmailSetting_From CHECK (FromAddress LIKE '%_@_%._%'),
    CONSTRAINT FK_TenantEmailSetting_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
