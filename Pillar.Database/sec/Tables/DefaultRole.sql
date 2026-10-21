-- Pillar's seeded roles (Owner, Admin, Manager, Billing, Member), copied to each tenant by sec.usp_SeedTenantRoles.
-- IsOwner: holds every permission, including ones added later; a tenant must keep at least one active owner.
CREATE TABLE sec.DefaultRole
(
    Code            VARCHAR(20)     NOT NULL CONSTRAINT PK_DefaultRole PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(50)    NOT NULL,
    Description     NVARCHAR(400)   NULL,
    IsOwner         BIT             NOT NULL CONSTRAINT DF_DefaultRole_IsOwner DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_DefaultRole_IsDefault DEFAULT (0),  -- preselected for new users
    SortOrder       INT             NOT NULL CONSTRAINT DF_DefaultRole_SortOrder DEFAULT (0)
);
