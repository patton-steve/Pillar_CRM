-- Pillar's own inbox (the back-office home): new applications, failed charges, support tickets and replies.
-- Pillar only: outside RLS, reached through the admin.usp_PlatformNotification_* procs.
-- SendEmail = 1 rows are also emailed to every platform admin (AppUser.IsPlatformAdmin = 1) by the API's email job, which
-- reads rows with EmailedAt NULL and marks them with admin.usp_PlatformNotification_MarkEmailed.
--   Kind  APPLICATION_SUBMITTED, PAYMENT_FAILED, SUPPORT_TICKET, SUPPORT_REPLY, CANCEL_REQUEST
CREATE TABLE admin.PlatformNotification
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlatformNotification PRIMARY KEY CLUSTERED,
    Kind            VARCHAR(30)     NOT NULL,
    TenantId        INT             NULL,
    EntityType      VARCHAR(20)     NULL,          -- TENANT, STATEMENT, TICKET
    EntityId        INT             NULL,
    Title           NVARCHAR(200)   NOT NULL,
    Body            NVARCHAR(2000)  NULL,
    DataJson        NVARCHAR(MAX)   NULL,          -- e.g. the application: company, tenant type, owner name and email
    SendEmail       BIT             NOT NULL CONSTRAINT DF_PlatformNotification_SendEmail DEFAULT (1),
    EmailedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_PlatformNotification_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ReadAt          DATETIME2(0)    NULL,
    ReadBy          INT             NULL,
    CONSTRAINT CK_PlatformNotification_Kind CHECK (Kind = 'APPLICATION_SUBMITTED' OR Kind = 'PAYMENT_FAILED' OR Kind = 'SUPPORT_TICKET'
        OR Kind = 'SUPPORT_REPLY' OR Kind = 'CANCEL_REQUEST'),
    CONSTRAINT CK_PlatformNotification_DataJson CHECK (DataJson IS NULL OR ISJSON(DataJson) = 1),
    CONSTRAINT FK_PlatformNotification_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_PlatformNotification_Unread ON admin.PlatformNotification (Id DESC) WHERE ReadAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_PlatformNotification_Email ON admin.PlatformNotification (Id) WHERE SendEmail = 1 AND EmailedAt IS NULL;
