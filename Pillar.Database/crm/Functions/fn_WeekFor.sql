-- The timesheet week that covers @Date for one person, without creating anything: their existing crm.Timesheet when there
-- is one (TimesheetId set), else the week crm.usp_Timesheet_Ensure would start from Timesheet.WeekStartDay (TimesheetId NULL).
CREATE FUNCTION crm.fn_WeekFor (@TenantId INT, @AppUserId INT, @Date DATE)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) w.TimesheetId, w.WeekStart, w.WeekEnd
    FROM (
        SELECT t.Id AS TimesheetId, t.WeekStart, t.WeekEnd, 1 AS Precedence
        FROM crm.Timesheet AS t
        WHERE t.TenantId = @TenantId AND t.AppUserId = @AppUserId AND t.WeekStart <= @Date AND t.WeekEnd >= @Date
        UNION ALL
        SELECT NULL, s.WeekStart, DATEADD(DAY, 6, s.WeekStart), 2
        FROM admin.fn_Setting(@TenantId, NULL, 'Timesheet.WeekStartDay') AS f
        CROSS APPLY (SELECT IIF(TRY_CONVERT(INT, f.Value) BETWEEN 1 AND 7, TRY_CONVERT(INT, f.Value), 1) AS StartDay) AS d
        -- 1900-01-01 was a Monday, so this is independent of @@DATEFIRST
        CROSS APPLY (SELECT DATEADD(DAY, -((DATEDIFF(DAY, '19000101', @Date) % 7 + 1 - d.StartDay + 7) % 7), @Date) AS WeekStart) AS s
    ) AS w
    ORDER BY w.Precedence;
