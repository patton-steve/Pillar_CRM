-- Files on a task (optionally posted with a comment). The file itself lives in blob storage under StorageKey;
-- the database keeps metadata only, so backups stay small and Azure Blob drops in later.
CREATE TABLE crm.TaskAttachment
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TaskAttachment PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TaskAttachment_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    TaskId          INT             NOT NULL,
    CommentId       INT             NULL,
    FileName        NVARCHAR(260)   NOT NULL,
    ContentType     NVARCHAR(100)   NOT NULL,
    SizeBytes       BIGINT          NOT NULL,
    StorageKey      NVARCHAR(400)   NOT NULL,  -- e.g. tenants/{TenantId}/tasks/{TaskPublicId}/{AttachmentPublicId}
    Sha256          BINARY(32)      NULL,
    UploadedBy      INT             NULL CONSTRAINT DF_TaskAttachment_UploadedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    UploadedAt      DATETIME2(0)    NOT NULL CONSTRAINT DF_TaskAttachment_UploadedAt DEFAULT (SYSUTCDATETIME()),
    DeletedAt       DATETIME2(0)    NULL,
    CONSTRAINT UQ_TaskAttachment_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_TaskAttachment_StorageKey UNIQUE (StorageKey),
    CONSTRAINT CK_TaskAttachment_SizeBytes CHECK (SizeBytes >= 0),
    CONSTRAINT FK_TaskAttachment_Task FOREIGN KEY (TenantId, TaskId) REFERENCES crm.ClientTask (TenantId, Id),
    -- a comment's attachment must be on the same task
    CONSTRAINT FK_TaskAttachment_Comment FOREIGN KEY (TenantId, TaskId, CommentId) REFERENCES crm.TaskComment (TenantId, TaskId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TaskAttachment_Task ON crm.TaskAttachment (TenantId, TaskId) WHERE DeletedAt IS NULL;
