-- A CSV import (phase 1: clients and contacts). The UI parses the file and maps columns, then stages the rows as JSON
-- (admin.usp_Import_Stage). Validate is a dry run that marks row errors; Commit creates the records for rows without errors.
-- Status: UPLOADED -> VALIDATED -> IMPORTED (or FAILED if the commit hit an unexpected error; the rows can be fixed and re-staged).
CREATE TABLE admin.ImportJob
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImportJob PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Kind            VARCHAR(10)     NOT NULL,
    FileName        NVARCHAR(260)   NULL,
    Status          VARCHAR(10)     NOT NULL CONSTRAINT DF_ImportJob_Status DEFAULT ('UPLOADED'),
    TotalRows       INT             NOT NULL CONSTRAINT DF_ImportJob_TotalRows DEFAULT (0),
    ErrorCount      INT             NOT NULL CONSTRAINT DF_ImportJob_ErrorCount DEFAULT (0),
    ImportedCount   INT             NOT NULL CONSTRAINT DF_ImportJob_ImportedCount DEFAULT (0),
    ValidatedAt     DATETIME2(0)    NULL,
    ImportedAt      DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ImportJob_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ImportJob_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT UQ_ImportJob_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_ImportJob_Kind CHECK (Kind = 'CLIENTS' OR Kind = 'CONTACTS'),
    CONSTRAINT CK_ImportJob_Status CHECK (Status = 'UPLOADED' OR Status = 'VALIDATED' OR Status = 'IMPORTED' OR Status = 'FAILED'),
    CONSTRAINT FK_ImportJob_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
