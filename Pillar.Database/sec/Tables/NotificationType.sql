-- Pillar's catalog of in-app notification types (seeded by the post-deploy script; global, not per tenant).
-- DefaultOn is what a user gets until they change it in their notification settings (sec.UserNotificationSetting).
-- Who receives each type is decided by sec.fn_NotificationRecipients. Channels (handoff 21): DefaultOn is in-app,
-- DefaultEmailOn is email; a tenant can override both and lock them on (admin.TenantNotificationDefault).
-- ActionKind tells the bell which quick-action buttons to show: APPROVE_TIMESHEET (Approve / Open), REPLY (reply inline).
CREATE TABLE sec.NotificationType
(
    Code            VARCHAR(40)     NOT NULL CONSTRAINT PK_NotificationType PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(100)   NOT NULL,
    Description     NVARCHAR(400)   NOT NULL,
    Category        NVARCHAR(50)    NOT NULL,      -- groups the settings page: Projects, Tasks, Time, Billing
    DefaultOn       BIT             NOT NULL,
    SortOrder       INT             NOT NULL,
    DefaultEmailOn  BIT             NOT NULL CONSTRAINT DF_NotificationType_DefaultEmailOn DEFAULT (0),   -- appended in handoff 21
    ActionKind      VARCHAR(20)     NULL,
    CONSTRAINT CK_NotificationType_ActionKind CHECK (ActionKind IS NULL OR ActionKind = 'APPROVE_TIMESHEET' OR ActionKind = 'REPLY')
);
