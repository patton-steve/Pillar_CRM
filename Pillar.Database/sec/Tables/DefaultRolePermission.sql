-- Which permissions each seeded role carries. Owner needs no rows (IsOwner covers everything).
CREATE TABLE sec.DefaultRolePermission
(
    RoleCode        VARCHAR(20)     NOT NULL,
    PermissionCode  VARCHAR(50)     NOT NULL,
    CONSTRAINT PK_DefaultRolePermission PRIMARY KEY CLUSTERED (RoleCode, PermissionCode),
    CONSTRAINT FK_DefaultRolePermission_Role FOREIGN KEY (RoleCode) REFERENCES sec.DefaultRole (Code),
    CONSTRAINT FK_DefaultRolePermission_Permission FOREIGN KEY (PermissionCode) REFERENCES sec.Permission (Code)
);
