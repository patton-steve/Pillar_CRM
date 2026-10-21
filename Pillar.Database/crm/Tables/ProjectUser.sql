-- Users allowed to log time to a project. Time entry is rejected for anyone not active here.
CREATE TABLE crm.ProjectUser
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProjectUser PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    ProjectId       INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    IsActive        BIT             NOT NULL CONSTRAINT DF_ProjectUser_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ProjectUser_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ProjectUser_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ProjectUser_Project_User UNIQUE (TenantId, ProjectId, AppUserId),
    CONSTRAINT FK_ProjectUser_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id),
    CONSTRAINT FK_ProjectUser_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_ProjectUser_User ON crm.ProjectUser (TenantId, AppUserId) WHERE IsActive = 1;
