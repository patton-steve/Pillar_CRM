-- A tenant's roles. Phase 1: only the seeded system roles (IsSystem = 1), kept in step with Pillar's defaults by
-- sec.usp_SeedTenantRoles. Tenant-defined roles come later (Steve 2026-10-20); the shape already allows them.
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
    CONSTRAINT UQ_Role_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Role_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_Role_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
