-- Comments / notes on a task, oldest first.
CREATE TABLE crm.TaskComment
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TaskComment PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    TaskId          INT             NOT NULL,
    AuthorUserId    INT             NULL CONSTRAINT DF_TaskComment_AuthorUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    Body            NVARCHAR(MAX)   NOT NULL,
    EditedAt        DATETIME2(0)    NULL,
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_TaskComment_CreatedAt DEFAULT (SYSUTCDATETIME()),
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_TaskComment_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_TaskComment_Tenant_Task_Id UNIQUE (TenantId, TaskId, Id),
    CONSTRAINT FK_TaskComment_Task FOREIGN KEY (TenantId, TaskId) REFERENCES crm.ClientTask (TenantId, Id),
    CONSTRAINT FK_TaskComment_AuthorUser FOREIGN KEY (TenantId, AuthorUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TaskComment_Task ON crm.TaskComment (TenantId, TaskId, CreatedAt);
