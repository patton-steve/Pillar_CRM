-- A person's uploaded avatar photo: a square crop made in the browser, PNG or JPEG, 256 KB max.
-- Shown when AppUser.AvatarKind = 'PHOTO'. Written by sec.usp_UserAvatar_Set, read by sec.usp_UserAvatar_Get.
CREATE TABLE sec.UserAvatar
(
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    ContentType     VARCHAR(20)     NOT NULL,
    Bytes           VARBINARY(MAX)  NOT NULL,
    UpdatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_UserAvatar_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserAvatar PRIMARY KEY CLUSTERED (TenantId, AppUserId),
    CONSTRAINT CK_UserAvatar_ContentType CHECK (ContentType = 'image/png' OR ContentType = 'image/jpeg'),
    CONSTRAINT CK_UserAvatar_Size CHECK (DATALENGTH(Bytes) <= 262144),
    CONSTRAINT FK_UserAvatar_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
