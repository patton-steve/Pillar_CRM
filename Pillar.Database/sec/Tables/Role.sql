-- A tenant's roles: the seeded system roles (IsSystem = 1), kept in step with Pillar's defaults by sec.usp_SeedTenantRoles,
-- plus roles the tenant adds (sec.usp_Role_Save, usually copied from a system role). BaseRoleCode is the archetype a
-- role behaves like (OWNER/ADMIN/MANAGER/BILLING/MEMBER). PermissionsCustomizedAt is set when an admin edits the
-- role's permission grid (sec.usp_RolePermission_Set); from then on the seed never adds permissions to it.
CREATE TABLE sec.Role
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Role PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            VARCHAR(20)     NOT NULL,
    Name            NVARCHAR(50)    NOT NULL,
    Description     NVARCHAR(400)   NULL,
    IsSystem        BIT             NOT NULL CONSTRAINT DF_Role_IsSystem DEFAULT (0),
    IsOwner         BIT             NOT NULL CONSTRAINT DF_Role_IsOwner DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_Role_IsDefault DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_Role_IsActive DEFAULT (1),
    SortOrder       INT             NOT NULL CONSTRAINT DF_Role_SortOrder DEFAULT (0),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Role_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt      DATETIME2(0)    NULL,
    BaseRoleCode    VARCHAR(20)     NULL,          -- last two columns appended in handoff 19
    PermissionsCustomizedAt DATETIME2(0) NULL,
    CONSTRAINT UQ_Role_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Role_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT CK_Role_BaseRoleCode CHECK (BaseRoleCode IS NULL OR BaseRoleCode = 'OWNER' OR BaseRoleCode = 'ADMIN'
        OR BaseRoleCode = 'MANAGER' OR BaseRoleCode = 'BILLING' OR BaseRoleCode = 'MEMBER'),
    CONSTRAINT FK_Role_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
