-- Who should hear about an event, before their own settings are applied (sec.usp_Notification_Raise does that):
--   BUDGET_THRESHOLD              PROJECT    the project manager and the client's account manager
--   PROJECT_CREATED_ON_MY_CLIENT  PROJECT    the client's account manager
--   TASK_CREATED_ON_MY_PROJECT    TASK       the project manager
--   TASK_ASSIGNED_TO_ME           TASK       the assignee
--   WATCHED_TASK_CHANGED          TASK       the task's watchers
--   MENTIONED                     COMMENT    people mentioned in the task comment
--   MENTIONED                     NOTE       people mentioned in the client note
--   TIMESHEET_SUBMITTED           TIMESHEET  everyone who can approve time
--   TIMESHEET_REJECTED            TIMESHEET  the timesheet's owner
--   INVOICE_PAID                  INVOICE    the client's account manager
--   BILL_AWAITING_APPROVAL        BILL       everyone who can approve bills
--   INVOICE_OVERDUE               INVOICE    the client's account manager; with none, everyone who can issue invoices
--   TIMESHEET_DUE                 TIMESHEET  the timesheet's owner (reminder to submit)
--   PILO_USAGE_NEAR_LIMIT         TENANT     everyone who manages Pillar billing (EntityId = TenantId)
--   PLAN_PAYMENT_FAILED           STATEMENT  everyone who manages Pillar billing (admin.PlatformStatement)
CREATE FUNCTION sec.fn_NotificationRecipients (@TenantId INT, @NotificationType VARCHAR(40), @EntityType VARCHAR(20), @EntityId INT)
RETURNS TABLE
AS
RETURN
    SELECT p.ProjectManagerUserId AS AppUserId
    FROM crm.ClientProject AS p
    WHERE @EntityType = 'PROJECT' AND @NotificationType = 'BUDGET_THRESHOLD'
      AND p.TenantId = @TenantId AND p.Id = @EntityId AND p.ProjectManagerUserId IS NOT NULL
    UNION ALL
    SELECT c.AccountManagerUserId
    FROM crm.ClientProject AS p
    JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
    WHERE @EntityType = 'PROJECT' AND (@NotificationType = 'BUDGET_THRESHOLD' OR @NotificationType = 'PROJECT_CREATED_ON_MY_CLIENT')
      AND p.TenantId = @TenantId AND p.Id = @EntityId AND c.AccountManagerUserId IS NOT NULL
    UNION ALL
    SELECT CASE @NotificationType WHEN 'TASK_CREATED_ON_MY_PROJECT' THEN p.ProjectManagerUserId ELSE t.AssignedUserId END
    FROM crm.ClientTask AS t
    JOIN crm.ClientProject AS p ON p.TenantId = t.TenantId AND p.Id = t.ProjectId
    WHERE @EntityType = 'TASK' AND (@NotificationType = 'TASK_CREATED_ON_MY_PROJECT' OR @NotificationType = 'TASK_ASSIGNED_TO_ME')
      AND t.TenantId = @TenantId AND t.Id = @EntityId
    UNION ALL
    SELECT w.AppUserId
    FROM crm.TaskWatcher AS w
    WHERE @EntityType = 'TASK' AND @NotificationType = 'WATCHED_TASK_CHANGED' AND w.TenantId = @TenantId AND w.TaskId = @EntityId
    UNION ALL
    SELECT m.AppUserId
    FROM crm.TaskCommentMention AS m
    WHERE @EntityType = 'COMMENT' AND @NotificationType = 'MENTIONED' AND m.TenantId = @TenantId AND m.CommentId = @EntityId
    UNION ALL
    SELECT m.AppUserId
    FROM crm.ClientNoteMention AS m
    WHERE @EntityType = 'NOTE' AND @NotificationType = 'MENTIONED' AND m.TenantId = @TenantId AND m.NoteId = @EntityId
    UNION ALL
    SELECT s.AppUserId
    FROM crm.Timesheet AS s
    WHERE @EntityType = 'TIMESHEET' AND (@NotificationType = 'TIMESHEET_REJECTED' OR @NotificationType = 'TIMESHEET_DUE')
      AND s.TenantId = @TenantId AND s.Id = @EntityId
    UNION ALL
    SELECT u.Id
    FROM sec.AppUser AS u
    CROSS APPLY sec.fn_UserHasPermission(u.TenantId, u.Id,
        CASE @NotificationType WHEN 'TIMESHEET_SUBMITTED' THEN 'time.approve' WHEN 'BILL_AWAITING_APPROVAL' THEN 'ap.approve'
                               ELSE 'billing.manage' END) AS ok
    WHERE ((@EntityType = 'TIMESHEET' AND @NotificationType = 'TIMESHEET_SUBMITTED')
        OR (@EntityType = 'BILL' AND @NotificationType = 'BILL_AWAITING_APPROVAL')
        OR (@EntityType = 'TENANT' AND @NotificationType = 'PILO_USAGE_NEAR_LIMIT' AND @EntityId = @TenantId)
        OR (@EntityType = 'STATEMENT' AND @NotificationType = 'PLAN_PAYMENT_FAILED'))
      AND u.TenantId = @TenantId
    UNION ALL
    SELECT c.AccountManagerUserId
    FROM ar.Invoice AS i
    JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
    WHERE @EntityType = 'INVOICE' AND (@NotificationType = 'INVOICE_PAID' OR @NotificationType = 'INVOICE_OVERDUE')
      AND i.TenantId = @TenantId AND i.Id = @EntityId AND c.AccountManagerUserId IS NOT NULL
    UNION ALL
    SELECT u.Id
    FROM ar.Invoice AS i
    JOIN crm.Client AS c ON c.TenantId = i.TenantId AND c.Id = i.ClientId
    JOIN sec.AppUser AS u ON u.TenantId = i.TenantId
    CROSS APPLY sec.fn_UserHasPermission(u.TenantId, u.Id, 'invoice.issue') AS ok
    WHERE @EntityType = 'INVOICE' AND @NotificationType = 'INVOICE_OVERDUE'
      AND i.TenantId = @TenantId AND i.Id = @EntityId AND c.AccountManagerUserId IS NULL;
