-- Every email Pillar sends for a tenant, one row per message (invoice emails first; credit memos, statements and
-- reminders later). The API queues a row, sends through the tenant's SMTP, then records SENT or FAILED.
-- EntityType + EntityId: INVOICE ar.Invoice, CREDIT_MEMO ar.CreditMemo. Feeds "Emailed to ..." on the invoice timeline
-- and the client activity feed. Written by admin.usp_EmailLog_Queue / usp_EmailLog_SetStatus.
CREATE TABLE admin.EmailLog
(
    Id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmailLog PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    EntityType      VARCHAR(20)     NOT NULL,
    EntityId        INT             NOT NULL,
    TemplateId      INT             NULL,
    ToAddresses     NVARCHAR(1000)  NOT NULL,      -- semicolon-separated
    CcAddresses     NVARCHAR(1000)  NULL,
    Subject         NVARCHAR(300)   NOT NULL,      -- as sent, tokens filled
    Status          VARCHAR(10)     NOT NULL CONSTRAINT DF_EmailLog_Status DEFAULT ('QUEUED'),
    Error           NVARCHAR(1000)  NULL,
    QueuedAt        DATETIME2(0)    NOT NULL CONSTRAINT DF_EmailLog_QueuedAt DEFAULT (SYSUTCDATETIME()),
    QueuedBy        INT             NULL CONSTRAINT DF_EmailLog_QueuedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    SentAt          DATETIME2(0)    NULL,
    CONSTRAINT CK_EmailLog_Status CHECK (Status = 'QUEUED' OR Status = 'SENT' OR Status = 'FAILED'),
    CONSTRAINT CK_EmailLog_EntityType CHECK (
        EntityType = 'INVOICE' OR EntityType = 'CREDIT_MEMO' OR EntityType = 'STATEMENT' OR EntityType = 'REMINDER'),
    CONSTRAINT FK_EmailLog_Template FOREIGN KEY (TenantId, TemplateId) REFERENCES admin.EmailTemplate (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_EmailLog_Entity ON admin.EmailLog (TenantId, EntityType, EntityId, QueuedAt);
GO
CREATE NONCLUSTERED INDEX IX_EmailLog_Queued ON admin.EmailLog (TenantId, QueuedAt) WHERE Status = 'QUEUED';
