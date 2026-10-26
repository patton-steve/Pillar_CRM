-- Headers of the Settings > Roles permission grid, in order. Pillar-owned and seeded by the post-deploy script; the UI
-- builds the grid only from this table and sec.Permission (sec.usp_RolePermission_Grid), so a new category or
-- permission shows up with no front-end change. IsActive = 0 hides a category (and its permissions) from the grid.
CREATE TABLE sec.PermissionCategory
(
    Code            VARCHAR(30)     NOT NULL CONSTRAINT PK_PermissionCategory PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(50)    NOT NULL,
    Description     NVARCHAR(400)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_PermissionCategory_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_PermissionCategory_IsActive DEFAULT (1)
);
