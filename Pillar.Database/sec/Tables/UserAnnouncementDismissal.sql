-- Announcements a person closed, so they stay hidden for them.
CREATE TABLE sec.UserAnnouncementDismissal
(
    TenantId        INT             NOT NULL,
    AppUserId       INT             NOT NULL,
    AnnouncementId  INT             NOT NULL,
    DismissedAt     DATETIME2(0)    NOT NULL CONSTRAINT DF_UserAnnouncementDismissal_DismissedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserAnnouncementDismissal PRIMARY KEY CLUSTERED (TenantId, AppUserId, AnnouncementId),
    CONSTRAINT FK_UserAnnouncementDismissal_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_UserAnnouncementDismissal_Announcement FOREIGN KEY (AnnouncementId) REFERENCES admin.Announcement (Id)
);
