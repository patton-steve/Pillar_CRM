-- Parameters the API passes when it renders an admin.Report. Source says where the value comes from:
--   SESSION  = the caller's session (TenantId)       RECORD = the record being rendered (e.g. Invoice.PublicId)
--   CONSTANT = DefaultValue as written                USER   = the person fills it in on the report viewer panel
-- USER parameters: Label is the panel caption; ListSource names a pick list the API fills (CLIENTS, PROJECTS, USERS,
-- VENDORS, TASK_STATUSES...), NULL = free entry of DataType; DefaultValue may be a literal or a date token the API
-- resolves (TODAY, WEEK_START, MONTH_START, LAST_MONTH_START, LAST_MONTH_END, YEAR_START).
CREATE TABLE admin.ReportParameter
(
    ReportId        INT             NOT NULL,
    Name            VARCHAR(50)     NOT NULL,      -- exactly as named in the RDL
    DataType        VARCHAR(10)     NOT NULL,
    Source          VARCHAR(10)     NOT NULL,
    SourceKey       VARCHAR(50)     NULL,          -- SESSION/RECORD: which value, e.g. TenantId, PublicId
    DefaultValue    NVARCHAR(400)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_ReportParameter_SortOrder DEFAULT (0),
    Label           NVARCHAR(100)   NULL,          -- last three columns appended in handoff 20
    ListSource      VARCHAR(50)     NULL,
    IsRequired      BIT             NOT NULL CONSTRAINT DF_ReportParameter_IsRequired DEFAULT (1),
    CONSTRAINT PK_ReportParameter PRIMARY KEY CLUSTERED (ReportId, Name),
    CONSTRAINT CK_ReportParameter_DataType CHECK (DataType IN ('INT', 'STRING', 'BIT', 'DECIMAL', 'DATE')),
    CONSTRAINT CK_ReportParameter_Source CHECK (Source = 'SESSION' OR Source = 'RECORD' OR Source = 'CONSTANT' OR Source = 'USER'),
    CONSTRAINT FK_ReportParameter_Report FOREIGN KEY (ReportId) REFERENCES admin.Report (Id)
);
