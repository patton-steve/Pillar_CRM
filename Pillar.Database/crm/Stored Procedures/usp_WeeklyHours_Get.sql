-- Today > "This week's hours vs goal": hours logged in the week that covers @WeekOf (default today in the tenant's time
-- zone) against Time.WeeklyHoursGoal (tenant default 40, a person can have their own). One row for the session user, or
-- with @AllUsers = 1 one row per active person (needs time.view_all). Running timers aren't counted.
--   LoggedHours    every entry in the week, as entered
--   BillableHours  billable entries, after rounding
CREATE PROCEDURE crm.usp_WeeklyHours_Get
    @WeekOf     DATE = NULL,
    @AllUsers   BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF @AllUsers = 1 AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.view_all'))
        THROW 52320, N'You need permission to see everyone''s time.', 1;

    IF @WeekOf IS NULL
        SELECT @WeekOf = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId AS DATE)
        FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    SELECT u.Id AS AppUserId, u.DisplayName, w.WeekStart, w.WeekEnd, w.TimesheetId, ts.SystemCode AS TimesheetStatus,
           CONVERT(DECIMAL(9,2), ISNULL(x.EnteredMinutes, 0) / 60.0) AS LoggedHours,
           CONVERT(DECIMAL(9,2), ISNULL(x.BillableMinutes, 0) / 60.0) AS BillableHours,
           g.GoalHours,
           CONVERT(DECIMAL(9,1), IIF(g.GoalHours > 0, ISNULL(x.EnteredMinutes, 0) / 60.0 * 100 / g.GoalHours, NULL)) AS PercentOfGoal
    FROM sec.AppUser AS u
    CROSS APPLY crm.fn_WeekFor(u.TenantId, u.Id, @WeekOf) AS w
    LEFT JOIN crm.Timesheet AS t ON t.TenantId = u.TenantId AND t.Id = w.TimesheetId
    LEFT JOIN lkp.TimesheetStatus AS ts ON ts.TenantId = t.TenantId AND ts.Id = t.TimesheetStatusId
    OUTER APPLY (
        SELECT SUM(e.EnteredMinutes) AS EnteredMinutes, SUM(IIF(e.IsBillable = 1, e.BilledMinutes, 0)) AS BillableMinutes
        FROM crm.TimeEntry AS e
        WHERE e.TenantId = u.TenantId AND e.TimesheetId = w.TimesheetId AND e.DeletedAt IS NULL
    ) AS x
    OUTER APPLY (
        SELECT TRY_CONVERT(DECIMAL(9,2), f.Value) AS GoalHours FROM admin.fn_Setting(u.TenantId, u.Id, 'Time.WeeklyHoursGoal') AS f
    ) AS g
    WHERE u.TenantId = @TenantId
      AND (u.Id = @UserId OR (@AllUsers = 1 AND u.Status = 'ACTIVE'))
    ORDER BY IIF(u.Id = @UserId, 0, 1), u.DisplayName;
END;
