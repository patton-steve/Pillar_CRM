-- A unit of work inside a project, handled like a Jira ticket. Flat (no subtasks).
-- TaskKey (e.g. PM-118) = project type KeyPrefix + per-tenant, per-prefix number. It is assigned once by
-- crm.usp_ClientTask_Create and never changes, even if the project's type changes later.
-- System-versioned: every change is kept in crm.ClientTaskHistory (status, assignee, estimate history).
CREATE TABLE crm.ClientTask
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientTask PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ClientTask_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    ProjectId       INT             NOT NULL,
    TaskKey         VARCHAR(20)     NOT NULL,
    TaskNumber      INT             NOT NULL,
    Title           NVARCHAR(200)   NOT NULL,
    Description     NVARCHAR(MAX)   NULL,
    TaskTypeId      INT             NULL,      -- drives rate resolution
    TaskStatusId    INT             NOT NULL,
    TaskPriorityId  INT             NULL,
    AssignedUserId  INT             NULL CONSTRAINT DF_ClientTask_AssignedUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),  -- defaults to creator
    ReporterUserId  INT             NULL CONSTRAINT DF_ClientTask_ReporterUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    EstimatedHours  DECIMAL(9,2)    NULL,
    StartDate       DATE            NULL,
    DueDate         DATE            NULL,
    CompletedAt     DATETIME2(0)    NULL,      -- maintained by crm.trg_ClientTask_CompletedAt
    IsBillable      BIT             NOT NULL,  -- defaults from the project in usp_ClientTask_Create
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ClientTask_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ClientTask_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    ValidFrom       DATETIME2(2)    GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    ValidTo         DATETIME2(2)    GENERATED ALWAYS AS ROW END HIDDEN NOT NULL,
    StepsToReplicate    NVARCHAR(MAX)   NULL,  -- rich text, shown beside Description on the task page
    ResolutionCriteria  NVARCHAR(MAX)   NULL,  -- rich text: what "done" means
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),
    CONSTRAINT UQ_ClientTask_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_ClientTask_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_ClientTask_Tenant_Project_Id UNIQUE (TenantId, ProjectId, Id),
    CONSTRAINT UQ_ClientTask_Tenant_TaskKey UNIQUE (TenantId, TaskKey),
    CONSTRAINT CK_ClientTask_EstimatedHours CHECK (EstimatedHours IS NULL OR EstimatedHours >= 0),
    CONSTRAINT CK_ClientTask_Dates CHECK (DueDate IS NULL OR StartDate IS NULL OR DueDate >= StartDate),
    CONSTRAINT FK_ClientTask_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id),
    CONSTRAINT FK_ClientTask_TaskType FOREIGN KEY (TenantId, TaskTypeId) REFERENCES lkp.TaskType (TenantId, Id),
    CONSTRAINT FK_ClientTask_TaskStatus FOREIGN KEY (TenantId, TaskStatusId) REFERENCES lkp.TaskStatus (TenantId, Id),
    CONSTRAINT FK_ClientTask_TaskPriority FOREIGN KEY (TenantId, TaskPriorityId) REFERENCES lkp.TaskPriority (TenantId, Id),
    CONSTRAINT FK_ClientTask_AssignedUser FOREIGN KEY (TenantId, AssignedUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_ClientTask_ReporterUser FOREIGN KEY (TenantId, ReporterUserId) REFERENCES sec.AppUser (TenantId, Id)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = crm.ClientTaskHistory, HISTORY_RETENTION_PERIOD = INFINITE));
GO
CREATE NONCLUSTERED INDEX IX_ClientTask_Project ON crm.ClientTask (TenantId, ProjectId) WHERE DeletedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_ClientTask_Assignee ON crm.ClientTask (TenantId, AssignedUserId, TaskStatusId) WHERE DeletedAt IS NULL;
