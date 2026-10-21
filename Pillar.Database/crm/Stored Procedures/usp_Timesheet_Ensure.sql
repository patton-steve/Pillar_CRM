-- Internal: returns the person's timesheet that covers @WorkDate, creating it if needed. Called by usp_TimeEntry_Save
-- inside its transaction. A new sheet starts on the tenant's Timesheet.WeekStartDay (1 = Monday ... 7 = Sunday) and is
-- trimmed so it never overlaps a sheet created under an earlier start day.
CREATE PROCEDURE crm.usp_Timesheet_Ensure
    @TenantId       INT,
    @AppUserId      INT,
    @WorkDate       DATE,
    @TimesheetId    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDay INT, @Start DATE, @End DATE, @PrevEnd DATE, @NextStart DATE;

    SELECT @TimesheetId = Id
    FROM crm.Timesheet WITH (UPDLOCK, HOLDLOCK)
    WHERE TenantId = @TenantId AND AppUserId = @AppUserId AND WeekStart <= @WorkDate AND WeekEnd >= @WorkDate;

    IF @TimesheetId IS NOT NULL RETURN;

    SELECT @StartDay = ISNULL(TRY_CONVERT(INT, Value), 1) FROM admin.fn_Setting(@TenantId, NULL, 'Timesheet.WeekStartDay');
    IF @StartDay IS NULL OR @StartDay < 1 OR @StartDay > 7 SET @StartDay = 1;

    -- 1900-01-01 was a Monday, so this is independent of @@DATEFIRST
    SET @Start = DATEADD(DAY, -((DATEDIFF(DAY, '19000101', @WorkDate) % 7 + 1 - @StartDay + 7) % 7), @WorkDate);
    SET @End = DATEADD(DAY, 6, @Start);

    SELECT @PrevEnd = MAX(WeekEnd) FROM crm.Timesheet WITH (UPDLOCK, HOLDLOCK)
    WHERE TenantId = @TenantId AND AppUserId = @AppUserId AND WeekEnd < @WorkDate AND WeekEnd >= @Start;
    SELECT @NextStart = MIN(WeekStart) FROM crm.Timesheet WITH (UPDLOCK, HOLDLOCK)
    WHERE TenantId = @TenantId AND AppUserId = @AppUserId AND WeekStart > @WorkDate AND WeekStart <= @End;

    IF @PrevEnd IS NOT NULL SET @Start = DATEADD(DAY, 1, @PrevEnd);
    IF @NextStart IS NOT NULL SET @End = DATEADD(DAY, -1, @NextStart);

    INSERT INTO crm.Timesheet (TenantId, AppUserId, WeekStart, WeekEnd, TimesheetStatusId)
    SELECT @TenantId, @AppUserId, @Start, @End, s.Id
    FROM lkp.TimesheetStatus AS s
    WHERE s.TenantId = @TenantId AND s.SystemCode = 'OPEN';

    SET @TimesheetId = SCOPE_IDENTITY();
    IF @TimesheetId IS NULL THROW 50581, N'Timesheet statuses are missing for this tenant (run lkp.usp_SyncTenantLookups).', 1;
END;
