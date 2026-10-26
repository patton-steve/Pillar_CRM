-- People following a task; they get WATCHED_TASK_CHANGED notifications. The assignee and reporter are added by
-- crm.trg_ClientTask_Watchers, commenters and mentioned people by crm.usp_TaskComment_Save; anyone can follow or
-- unfollow with crm.usp_TaskWatcher_Set.
CREATE TABLE crm.TaskWatcher
(
    TenantId        INT             NOT NULL,
    TaskId          INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    AddedAt         DATETIME2(0)    NOT NULL CONSTRAINT DF_TaskWatcher_AddedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_TaskWatcher PRIMARY KEY CLUSTERED (TenantId, TaskId, AppUserId),
    CONSTRAINT FK_TaskWatcher_Task FOREIGN KEY (TenantId, TaskId) REFERENCES crm.ClientTask (TenantId, Id),
    CONSTRAINT FK_TaskWatcher_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TaskWatcher_User ON crm.TaskWatcher (TenantId, AppUserId);
