-- The @name parameters of a saved Pilo report's SqlText (handoff 24), shown on the report's viewer panel. Replaced as a set
-- by admin.usp_SavedReport_Save (@Parameters). The values a person last used stay in SavedReport.ParameterJson.
--   DataType     DATE, INT, DECIMAL, STRING, BIT, or a pick list: CLIENT, PROJECT, USER, VENDOR (the value is the Id)
--   DefaultValue a literal, or for DATE a token: TODAY, WEEK_START, MONTH_START, LAST_MONTH_START, LAST_MONTH_END, YEAR_START
CREATE TABLE admin.SavedReportParameter
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SavedReportParameter PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    SavedReportId   INT             NOT NULL,
    Name            VARCHAR(50)     NOT NULL,      -- used in the SQL as @Name
    Label           NVARCHAR(100)   NOT NULL,
    DataType        VARCHAR(10)     NOT NULL,
    DefaultValue    NVARCHAR(200)   NULL,
    IsRequired      BIT             NOT NULL CONSTRAINT DF_SavedReportParameter_IsRequired DEFAULT (1),
    SortOrder       INT             NOT NULL CONSTRAINT DF_SavedReportParameter_SortOrder DEFAULT (0),
    CONSTRAINT UQ_SavedReportParameter_Name UNIQUE (TenantId, SavedReportId, Name),
    CONSTRAINT CK_SavedReportParameter_Name CHECK (Name NOT LIKE '%[^A-Za-z0-9_]%' AND Name LIKE '[A-Za-z]%'),
    CONSTRAINT CK_SavedReportParameter_DataType CHECK (DataType = 'DATE' OR DataType = 'INT' OR DataType = 'DECIMAL'
        OR DataType = 'STRING' OR DataType = 'BIT' OR DataType = 'CLIENT' OR DataType = 'PROJECT' OR DataType = 'USER'
        OR DataType = 'VENDOR'),
    CONSTRAINT FK_SavedReportParameter_Report FOREIGN KEY (TenantId, SavedReportId) REFERENCES admin.SavedReport (TenantId, Id)
);
