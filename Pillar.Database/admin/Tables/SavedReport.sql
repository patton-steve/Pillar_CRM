-- Pilo AI reports people saved from the Reports page. IsShared = 0: "My saved AI reports" (owner only);
-- IsShared = 1: "Company AI reports" (everyone in the tenant can run it). Definition is what Pilo generated
-- (query/report definition JSON), so a saved report re-runs without asking Pilo again; ParameterJson holds the
-- parameter values saved with it. Limits come from plan-derived settings Pilo.SavedReportsPerUser (5/10/25) and
-- Pilo.CompanyReports (50 on Enterprise, 0 below), enforced by admin.usp_SavedReport_Save.
-- RenderType is the "Show it as" choice (admin.ReportRenderType); NULL = Pilo chose.
CREATE TABLE admin.SavedReport
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SavedReport PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_SavedReport_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId        INT             NOT NULL,
    OwnerUserId     INT             NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    Prompt          NVARCHAR(2000)  NOT NULL,
    Definition      NVARCHAR(MAX)   NOT NULL,
    ParameterJson   NVARCHAR(MAX)   NULL,
    IsShared        BIT             NOT NULL CONSTRAINT DF_SavedReport_IsShared DEFAULT (0),
    LastRunAt       DATETIME2(0)    NULL,
    RunCount        INT             NOT NULL CONSTRAINT DF_SavedReport_RunCount DEFAULT (0),
    DeletedAt       DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_SavedReport_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_SavedReport_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    RenderType      VARCHAR(30)     NULL,          -- appended in handoff 20
    CONSTRAINT UQ_SavedReport_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_SavedReport_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_SavedReport_Definition CHECK (ISJSON(Definition) = 1),
    CONSTRAINT CK_SavedReport_ParameterJson CHECK (ParameterJson IS NULL OR ISJSON(ParameterJson) = 1),
    CONSTRAINT FK_SavedReport_RenderType FOREIGN KEY (RenderType) REFERENCES admin.ReportRenderType (Code),
    CONSTRAINT FK_SavedReport_Owner FOREIGN KEY (TenantId, OwnerUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_SavedReport_Owner ON admin.SavedReport (TenantId, OwnerUserId, IsShared) WHERE DeletedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_SavedReport_Shared ON admin.SavedReport (TenantId, IsShared) WHERE DeletedAt IS NULL;
