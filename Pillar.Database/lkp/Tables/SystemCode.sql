-- Pillar-owned behaviors a lookup value can map to. Tenants can add any number of statuses,
-- but each one maps to a row here, and procs and the API only ever test SystemCode.
-- Adding a behavior = one row here plus the code that honors it.
CREATE TABLE lkp.SystemCode
(
    LookupName      VARCHAR(50)     NOT NULL,
    SystemCode      VARCHAR(30)     NOT NULL,
    Description     NVARCHAR(400)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_SystemCode_SortOrder DEFAULT (0),
    CONSTRAINT PK_SystemCode PRIMARY KEY CLUSTERED (LookupName, SystemCode)
);
