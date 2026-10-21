-- Permissions granted to a tenant role.
CREATE TABLE sec.RolePermission
(
    TenantId        INT             NOT NULL,
    RoleId          INT             NOT NULL,
    PermissionCode  VARCHAR(50)     NOT NULL,
    CONSTRAINT PK_RolePermission PRIMARY KEY CLUSTERED (TenantId, RoleId, PermissionCode),
    CONSTRAINT FK_RolePermission_Role FOREIGN KEY (TenantId, RoleId) REFERENCES sec.Role (TenantId, Id),
    CONSTRAINT FK_RolePermission_Permission FOREIGN KEY (PermissionCode) REFERENCES sec.Permission (Code)
);
