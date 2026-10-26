-- A tenant's own default for one notification type and channel (Settings > Notification defaults, settings.notifications).
-- IsLocked = 1 forces the channel on for everyone: people see it switched on and can't turn it off.
-- No row = Pillar's default on sec.NotificationType. Written by admin.usp_TenantNotificationDefault_Set.
CREATE TABLE admin.TenantNotificationDefault
(
    TenantId            INT             NOT NULL,
    NotificationType    VARCHAR(40)     NOT NULL,
    Channel             VARCHAR(10)     NOT NULL,      -- IN_APP, EMAIL
    IsOn                BIT             NOT NULL,
    IsLocked            BIT             NOT NULL CONSTRAINT DF_TenantNotificationDefault_IsLocked DEFAULT (0),
    ModifiedAt          DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantNotificationDefault_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedBy          INT             NULL CONSTRAINT DF_TenantNotificationDefault_ModifiedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT PK_TenantNotificationDefault PRIMARY KEY CLUSTERED (TenantId, NotificationType, Channel),
    CONSTRAINT CK_TenantNotificationDefault_Channel CHECK (Channel = 'IN_APP' OR Channel = 'EMAIL'),
    CONSTRAINT CK_TenantNotificationDefault_Lock CHECK (IsLocked = 0 OR IsOn = 1),
    CONSTRAINT FK_TenantNotificationDefault_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_TenantNotificationDefault_Type FOREIGN KEY (NotificationType) REFERENCES sec.NotificationType (Code)
);
