-- The last pages a user opened, for the "Recent" list. sec.usp_RecentItem_Touch upserts and keeps the newest 25 per user.
-- EntityType is the app's own name for the record kind (client, project, task, invoice, bill...).
CREATE TABLE sec.UserRecentItem
(
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    EntityType      VARCHAR(30)     NOT NULL,
    EntityPublicId  UNIQUEIDENTIFIER NOT NULL,
    Title           NVARCHAR(200)   NOT NULL,
    VisitedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_UserRecentItem_VisitedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserRecentItem PRIMARY KEY CLUSTERED (TenantId, AppUserId, EntityType, EntityPublicId),
    CONSTRAINT FK_UserRecentItem_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_UserRecentItem_Visited ON sec.UserRecentItem (TenantId, AppUserId, VisitedAt DESC);
