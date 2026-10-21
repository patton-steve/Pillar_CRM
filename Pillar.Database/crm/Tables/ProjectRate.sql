-- Rates by person and/or task type with history. Resolution at time entry (most specific wins):
-- user + task type -> user -> task type -> ClientProject.DefaultRate. The resolved rate is copied to TimeEntry.
-- Overlapping date ranges for the same (project, user, task type) are rejected by crm.trg_ProjectRate_NoOverlap.
CREATE TABLE crm.ProjectRate
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProjectRate PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    ProjectId       INT             NOT NULL,
    AppUserId       INT             NULL,
    TaskTypeId      INT             NULL,
    Rate            DECIMAL(19,4)   NOT NULL,
    EffectiveFrom   DATE            NOT NULL,
    EffectiveTo     DATE            NULL,      -- NULL = open-ended
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ProjectRate_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ProjectRate_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ProjectRate_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_ProjectRate_Rate CHECK (Rate >= 0),
    CONSTRAINT CK_ProjectRate_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
    CONSTRAINT FK_ProjectRate_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id),
    CONSTRAINT FK_ProjectRate_TaskType FOREIGN KEY (TenantId, TaskTypeId) REFERENCES lkp.TaskType (TenantId, Id),
    CONSTRAINT FK_ProjectRate_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_ProjectRate_Lookup
    ON crm.ProjectRate (TenantId, ProjectId, AppUserId, TaskTypeId, EffectiveFrom) INCLUDE (EffectiveTo, Rate);
