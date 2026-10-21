-- Pillar-owned catalog of what a user can do. The API checks permissions (sec.fn_UserHasPermission), never role names,
-- so tenant-defined roles can come later without code changes. Seeded by the post-deploy script.
CREATE TABLE sec.Permission
(
    Code            VARCHAR(50)     NOT NULL CONSTRAINT PK_Permission PRIMARY KEY CLUSTERED,   -- area.action, e.g. time.approve
    Category        NVARCHAR(50)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    Description     NVARCHAR(400)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_Permission_SortOrder DEFAULT (0)
);
