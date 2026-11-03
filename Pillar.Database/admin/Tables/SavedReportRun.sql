-- One row per run of a saved Pilo report (handoff 24), written by admin.usp_SavedReport_MarkRun after the API runs SqlText on
-- the pillar_ai_reader connection. Re-runs never call the model, so they aren't Pilo usage. Succeeded = 0 keeps the error
-- (for example, a view column that changed since the report was saved).
CREATE TABLE admin.SavedReportRun
(
    Id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SavedReportRun PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    SavedReportId   INT             NOT NULL,
    RunBy           INT             NULL CONSTRAINT DF_SavedReportRun_RunBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    RunAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_SavedReportRun_RunAt DEFAULT (SYSUTCDATETIME()),
    ParameterJson   NVARCHAR(MAX)   NULL,
    [RowCount]      INT             NULL,
    DurationMs      INT             NULL,
    Succeeded       BIT             NOT NULL CONSTRAINT DF_SavedReportRun_Succeeded DEFAULT (1),
    ErrorText       NVARCHAR(1000)  NULL,
    CONSTRAINT CK_SavedReportRun_ParameterJson CHECK (ParameterJson IS NULL OR ISJSON(ParameterJson) = 1),
    CONSTRAINT CK_SavedReportRun_Counts CHECK (([RowCount] IS NULL OR [RowCount] >= 0) AND (DurationMs IS NULL OR DurationMs >= 0)),
    CONSTRAINT FK_SavedReportRun_Report FOREIGN KEY (TenantId, SavedReportId) REFERENCES admin.SavedReport (TenantId, Id),
    CONSTRAINT FK_SavedReportRun_RunBy FOREIGN KEY (TenantId, RunBy) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_SavedReportRun_Report ON admin.SavedReportRun (TenantId, SavedReportId, RunAt DESC);
