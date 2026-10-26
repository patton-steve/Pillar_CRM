-- The header bell: one row per recipient per event, newest first. Created only by sec.usp_Notification_Raise, which
-- applies the recipient's settings. EntityType + EntityId say what the notification opens:
--   PROJECT crm.ClientProject  TASK crm.ClientTask  COMMENT crm.TaskComment  NOTE crm.ClientNote
--   TIMESHEET crm.Timesheet    INVOICE ar.Invoice   BILL ap.Bill   STATEMENT admin.PlatformStatement   TENANT admin.Tenant
-- SendEmail = the recipient gets it by email too; EmailedAt marks it sent (one by one, or in their digest). A recipient who
-- wants email but not in-app gets a row that is dismissed from the start, so only the email job sees it.
-- Users read and mark only their own rows, through sec.usp_Notification_List / usp_Notification_MarkRead.
CREATE TABLE sec.Notification
(
    Id                  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Notification PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    AppUserId           INT             NOT NULL,      -- recipient
    NotificationType    VARCHAR(40)     NOT NULL,
    Title               NVARCHAR(200)   NOT NULL,
    Body                NVARCHAR(1000)  NULL,
    EntityType          VARCHAR(20)     NULL,
    EntityId            INT             NULL,
    ActorUserId         INT             NULL,          -- who caused it; NULL for system events such as budget alerts
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_Notification_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ReadAt              DATETIME2(0)    NULL,
    DismissedAt         DATETIME2(0)    NULL,
    SendEmail           BIT             NOT NULL CONSTRAINT DF_Notification_SendEmail DEFAULT (0),   -- appended in handoff 21
    EmailedAt           DATETIME2(0)    NULL,
    CONSTRAINT CK_Notification_Entity CHECK ((EntityType IS NULL AND EntityId IS NULL) OR (EntityType IS NOT NULL AND EntityId IS NOT NULL)),
    CONSTRAINT FK_Notification_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_Notification_Type FOREIGN KEY (NotificationType) REFERENCES sec.NotificationType (Code)
);
GO
CREATE NONCLUSTERED INDEX IX_Notification_Recipient ON sec.Notification (TenantId, AppUserId, Id DESC)
    INCLUDE (ReadAt) WHERE DismissedAt IS NULL;
GO
-- the email job: unsent email notifications
CREATE NONCLUSTERED INDEX IX_Notification_EmailPending ON sec.Notification (TenantId, AppUserId, Id)
    WHERE SendEmail = 1 AND EmailedAt IS NULL;
