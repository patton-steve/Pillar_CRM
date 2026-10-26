-- One staged CSV row of an admin.ImportJob, already mapped to Pillar field names by the UI:
--   CLIENTS   {"clientCode","name","clientType","status","industry","website","taxId","notes","firstName","lastName"}
--   CONTACTS  {"clientCode","firstName","lastName","title","email","phone","mobile","role","isPrimary"}
-- Lookups (clientType, status, industry, role) match the tenant's list by code or name. ErrorText lists every problem
-- found by admin.usp_Import_Validate ("; "-separated); CreatedEntityId is the client or contact made by the commit.
CREATE TABLE admin.ImportRow
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImportRow PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    JobId           INT             NOT NULL,
    RowNumber       INT             NOT NULL,      -- line in the file, for the error list
    RawJson         NVARCHAR(MAX)   NOT NULL,
    ErrorText       NVARCHAR(1000)  NULL,
    CreatedEntityId INT             NULL,
    CONSTRAINT UQ_ImportRow_Job_Row UNIQUE (TenantId, JobId, RowNumber),
    CONSTRAINT CK_ImportRow_RawJson CHECK (ISJSON(RawJson) = 1),
    CONSTRAINT FK_ImportRow_Job FOREIGN KEY (TenantId, JobId) REFERENCES admin.ImportJob (TenantId, Id)
);
