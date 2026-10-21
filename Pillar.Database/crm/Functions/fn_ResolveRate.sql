-- Rate for a time entry on a date, most specific first:
-- ProjectRate user + task type -> user -> task type -> ClientProject.DefaultRate. No row = no rate found.
CREATE FUNCTION crm.fn_ResolveRate (@TenantId INT, @ProjectId INT, @AppUserId INT, @TaskTypeId INT, @WorkDate DATE)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) c.Rate, c.RateSource
    FROM (
        SELECT r.Rate,
               CASE WHEN r.AppUserId IS NOT NULL AND r.TaskTypeId IS NOT NULL THEN 'USER_TASK'
                    WHEN r.AppUserId IS NOT NULL THEN 'USER'
                    ELSE 'TASK' END AS RateSource,
               CASE WHEN r.AppUserId IS NOT NULL AND r.TaskTypeId IS NOT NULL THEN 1
                    WHEN r.AppUserId IS NOT NULL THEN 2
                    ELSE 3 END AS Precedence
        FROM crm.ProjectRate AS r
        WHERE r.TenantId = @TenantId AND r.ProjectId = @ProjectId
          AND (r.AppUserId = @AppUserId OR r.AppUserId IS NULL)
          AND (r.TaskTypeId = @TaskTypeId OR r.TaskTypeId IS NULL)
          AND (r.AppUserId IS NOT NULL OR r.TaskTypeId IS NOT NULL)
          AND @WorkDate >= r.EffectiveFrom AND (r.EffectiveTo IS NULL OR @WorkDate <= r.EffectiveTo)
        UNION ALL
        SELECT p.DefaultRate, 'PROJECT', 4
        FROM crm.ClientProject AS p
        WHERE p.TenantId = @TenantId AND p.Id = @ProjectId AND p.DefaultRate IS NOT NULL
    ) AS c
    ORDER BY c.Precedence;
