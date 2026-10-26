-- Optional checklist on a task (tasks stay flat; this is not subtasks). Saved as a whole list by crm.usp_TaskChecklist_Save.
CREATE TABLE crm.TaskChecklistItem
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TaskChecklistItem PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    TaskId          INT             NOT NULL,
    ItemText        NVARCHAR(500)   NOT NULL,
    IsDone          BIT             NOT NULL CONSTRAINT DF_TaskChecklistItem_IsDone DEFAULT (0),
    SortOrder       INT             NOT NULL,
    DoneAt          DATETIME2(0)    NULL,
    DoneBy          INT             NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_TaskChecklistItem_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_TaskChecklistItem_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT UQ_TaskChecklistItem_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_TaskChecklistItem_Done CHECK ((IsDone = 1 AND DoneAt IS NOT NULL) OR (IsDone = 0 AND DoneAt IS NULL AND DoneBy IS NULL)),
    CONSTRAINT FK_TaskChecklistItem_Task FOREIGN KEY (TenantId, TaskId) REFERENCES crm.ClientTask (TenantId, Id),
    CONSTRAINT FK_TaskChecklistItem_DoneBy FOREIGN KEY (TenantId, DoneBy) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TaskChecklistItem_Task ON crm.TaskChecklistItem (TenantId, TaskId, SortOrder);
