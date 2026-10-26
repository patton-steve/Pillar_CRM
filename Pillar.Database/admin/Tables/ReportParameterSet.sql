-- A person's saved parameter values for a canned report ("Last month, Acme only"). ReportCode is the canned report's
-- code (admin.Report.Code for SSRS reports, or the UI's key for a built-in report page), so there is no FK.
-- Private to the person. Write through admin.usp_ReportParameterSet_Save.
CREATE TABLE admin.ReportParameterSet
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReportParameterSet PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    ReportCode      VARCHAR(40)     NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    ParameterJson   NVARCHAR(MAX)   NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ReportParameterSet_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt      DATETIME2(0)    NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ReportParameterSet_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_ReportParameterSet_Name UNIQUE (TenantId, AppUserId, ReportCode, Name),
    CONSTRAINT CK_ReportParameterSet_ParameterJson CHECK (ISJSON(ParameterJson) = 1),
    CONSTRAINT FK_ReportParameterSet_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
