-- Comments / notes on a task, oldest first (the task page's All Notes tab). Body is rich text: HTML the API sanitizes
-- before saving; inline images are crm.TaskAttachment rows the HTML references. Write through crm.usp_TaskComment_Save.
-- A details edit (crm.usp_ClientTask_UpdateDetails) posts a comment whose ChangeJson lists the change chips,
-- [{"field":"Status","from":"To do","to":"In progress"}]; its Body is the editor's note, or '' when they wrote none.
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
    ChangeJson      NVARCHAR(MAX)   NULL,
    CONSTRAINT UQ_TaskComment_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_TaskComment_Tenant_Task_Id UNIQUE (TenantId, TaskId, Id),
    CONSTRAINT CK_TaskComment_ChangeJson CHECK (ChangeJson IS NULL OR ISJSON(ChangeJson) = 1),
    CONSTRAINT FK_TaskComment_Task FOREIGN KEY (TenantId, TaskId) REFERENCES crm.ClientTask (TenantId, Id),
    CONSTRAINT FK_TaskComment_AuthorUser FOREIGN KEY (TenantId, AuthorUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TaskComment_Task ON crm.TaskComment (TenantId, TaskId, CreatedAt);
