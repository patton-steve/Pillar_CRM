-- A user's choices for one notification type: IsOn = in-app, EmailOn = email (NULL = not chosen). Unset falls back to the
-- tenant default (admin.TenantNotificationDefault), then the type's DefaultOn / DefaultEmailOn; a channel the tenant locked
-- on can't be turned off. Resolved by sec.fn_NotificationChannels; written by sec.usp_NotificationSetting_Set.
CREATE TABLE sec.UserNotificationSetting
(
    TenantId            INT             NOT NULL,
    AppUserId           INT             NOT NULL,
    NotificationType    VARCHAR(40)     NOT NULL,
    IsOn                BIT             NOT NULL,
    ModifiedAt          DATETIME2(0)    NOT NULL CONSTRAINT DF_UserNotificationSetting_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    EmailOn             BIT             NULL,      -- appended in handoff 21
    CONSTRAINT PK_UserNotificationSetting PRIMARY KEY CLUSTERED (TenantId, AppUserId, NotificationType),
    CONSTRAINT FK_UserNotificationSetting_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_UserNotificationSetting_Type FOREIGN KEY (NotificationType) REFERENCES sec.NotificationType (Code)
);
