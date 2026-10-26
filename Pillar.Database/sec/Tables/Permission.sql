-- Pillar-owned catalog of what a user can do. The API checks permissions (sec.fn_UserHasPermission), never role names,
-- so tenant roles need no code changes. Seeded by the post-deploy script. CategoryCode places it under a
-- sec.PermissionCategory header in the role grid; Category (text) mirrors the category name for older readers.
-- IsActive = 0 retires a permission: it stops counting everywhere and leaves the grid, but grants are kept.
CREATE TABLE sec.Permission
(
    Code            VARCHAR(50)     NOT NULL CONSTRAINT PK_Permission PRIMARY KEY CLUSTERED,   -- area.action, e.g. time.approve
    Category        NVARCHAR(50)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    Description     NVARCHAR(400)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_Permission_SortOrder DEFAULT (0),
    CategoryCode    VARCHAR(30)     NULL,          -- last two columns appended in handoff 20; the seed fills CategoryCode
    IsActive        BIT             NOT NULL CONSTRAINT DF_Permission_IsActive DEFAULT (1),
    CONSTRAINT FK_Permission_Category FOREIGN KEY (CategoryCode) REFERENCES sec.PermissionCategory (Code)
);
