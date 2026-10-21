-- Pillar-owned kinds of tenant, picked at sign-up. Each type seeds different starting settings
-- (admin.TenantTypeSettingDefault), e.g. Independent Contractor starts with time approval off.
CREATE TABLE admin.TenantType
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TenantType PRIMARY KEY CLUSTERED,
    Code            VARCHAR(20)     NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    Description     NVARCHAR(400)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_TenantType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_TenantType_IsActive DEFAULT (1),   -- offered at sign-up
    CONSTRAINT UQ_TenantType_Code UNIQUE (Code)
);
