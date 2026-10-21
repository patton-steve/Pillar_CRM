-- Parameters the API passes when it renders an admin.Report. Source says where the value comes from:
--   SESSION  = the caller's session (TenantId)       RECORD = the record being rendered (e.g. Invoice.PublicId)
--   CONSTANT = DefaultValue as written
CREATE TABLE admin.ReportParameter
(
    ReportId        INT             NOT NULL,
    Name            VARCHAR(50)     NOT NULL,      -- exactly as named in the RDL
    DataType        VARCHAR(10)     NOT NULL,
    Source          VARCHAR(10)     NOT NULL,
    SourceKey       VARCHAR(50)     NULL,          -- SESSION/RECORD: which value, e.g. TenantId, PublicId
    DefaultValue    NVARCHAR(400)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_ReportParameter_SortOrder DEFAULT (0),
    CONSTRAINT PK_ReportParameter PRIMARY KEY CLUSTERED (ReportId, Name),
    CONSTRAINT CK_ReportParameter_DataType CHECK (DataType IN ('INT', 'STRING', 'BIT', 'DECIMAL', 'DATE')),
    CONSTRAINT CK_ReportParameter_Source CHECK (Source IN ('SESSION', 'RECORD', 'CONSTANT')),
    CONSTRAINT FK_ReportParameter_Report FOREIGN KEY (ReportId) REFERENCES admin.Report (Id)
);
