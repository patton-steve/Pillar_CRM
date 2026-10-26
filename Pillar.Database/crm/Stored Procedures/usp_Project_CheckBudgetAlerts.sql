-- Announces budget thresholds a project has crossed, once each (BUDGET_THRESHOLD to the project manager and the client's
-- account manager). Thresholds come from ClientProject.BudgetAlertPercents, else the tenant setting
-- Project.BudgetAlertPercents (default 80,100). Usage counts all logged time that isn't rejected: hours against
-- BudgetHours, billable amount against BudgetAmount. When usage falls back under a threshold (budget raised, time
-- rejected), that threshold is re-armed. The API calls it after saving or approving time (@ProjectId) and nightly
-- for each tenant (@ProjectId NULL = every project of the session tenant).
CREATE PROCEDURE crm.usp_Project_CheckBudgetAlerts
    @ProjectId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @TenantPercents VARCHAR(100);
    IF @TenantId IS NULL THROW 51331, N'SESSION_CONTEXT TenantId is not set.', 1;
    SELECT @TenantPercents = CONVERT(VARCHAR(100), Value) FROM admin.fn_Setting(@TenantId, NULL, 'Project.BudgetAlertPercents');

    CREATE TABLE #use (ProjectId INT, Basis VARCHAR(10), UsedPercent DECIMAL(9,2), Percents VARCHAR(100), Label NVARCHAR(250),
                       PRIMARY KEY (ProjectId, Basis));
    INSERT INTO #use (ProjectId, Basis, UsedPercent, Percents, Label)
    SELECT p.Id, b.Basis, CONVERT(DECIMAL(9,2), ROUND(100.0 * b.Used / b.Budget, 2)),
           COALESCE(p.BudgetAlertPercents, @TenantPercents), CONCAT(p.ProjectCode, N' ', p.Name)
    FROM crm.ClientProject AS p
    OUTER APPLY (SELECT SUM(e.Hours) AS Hours, SUM(e.AmountBillable) AS Amount
                 FROM crm.TimeEntry AS e
                 JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
                 WHERE e.TenantId = p.TenantId AND e.ProjectId = p.Id AND e.DeletedAt IS NULL AND s.SystemCode <> 'REJECTED') AS u
    CROSS APPLY (VALUES ('HOURS', p.BudgetHours, ISNULL(u.Hours, 0)), ('AMOUNT', p.BudgetAmount, ISNULL(u.Amount, 0))) AS b (Basis, Budget, Used)
    WHERE p.TenantId = @TenantId AND p.DeletedAt IS NULL AND (@ProjectId IS NULL OR p.Id = @ProjectId) AND b.Budget > 0;

    CREATE TABLE #hit (ProjectId INT, Basis VARCHAR(10), ThresholdPercent INT, UsedPercent DECIMAL(9,2), IsNew BIT,
                       PRIMARY KEY (ProjectId, Basis, ThresholdPercent));
    INSERT INTO #hit (ProjectId, Basis, ThresholdPercent, UsedPercent, IsNew)
    SELECT DISTINCT u.ProjectId, u.Basis, t.Pct, u.UsedPercent,
           IIF(EXISTS (SELECT 1 FROM crm.ProjectBudgetAlert AS a WHERE a.TenantId = @TenantId AND a.ProjectId = u.ProjectId
                       AND a.Basis = u.Basis AND a.ThresholdPercent = t.Pct), 0, 1)
    FROM #use AS u
    CROSS APPLY (SELECT TRY_CONVERT(INT, LTRIM(RTRIM(value))) AS Pct FROM STRING_SPLIT(u.Percents, ',')) AS t
    WHERE t.Pct >= 1 AND t.Pct <= 1000 AND u.UsedPercent >= t.Pct;

    BEGIN TRAN;

    -- re-arm thresholds usage has dropped back under
    DELETE a FROM crm.ProjectBudgetAlert AS a
    WHERE a.TenantId = @TenantId AND (@ProjectId IS NULL OR a.ProjectId = @ProjectId)
      AND NOT EXISTS (SELECT 1 FROM #hit AS h WHERE h.ProjectId = a.ProjectId AND h.Basis = a.Basis AND h.ThresholdPercent = a.ThresholdPercent);

    INSERT INTO crm.ProjectBudgetAlert (TenantId, ProjectId, Basis, ThresholdPercent, UsedPercent)
    SELECT @TenantId, ProjectId, Basis, ThresholdPercent, UsedPercent FROM #hit WHERE IsNew = 1;

    -- one notification per project and basis, for the highest newly crossed threshold
    DECLARE @ev TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, ProjectId INT, Title NVARCHAR(200));
    INSERT INTO @ev (ProjectId, Title)
    SELECT h.ProjectId, LEFT(CONCAT(u.Label, N' has used ', FORMAT(h.UsedPercent, '0.#'), N'% of its budget ',
                                    IIF(h.Basis = 'HOURS', N'hours', N'amount')), 200)
    FROM #hit AS h
    JOIN #use AS u ON u.ProjectId = h.ProjectId AND u.Basis = h.Basis
    WHERE h.IsNew = 1
      AND h.ThresholdPercent = (SELECT MAX(x.ThresholdPercent) FROM #hit AS x WHERE x.ProjectId = h.ProjectId AND x.Basis = h.Basis AND x.IsNew = 1);

    DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @ev), @Pid INT, @Title NVARCHAR(200);
    WHILE @i <= @n
    BEGIN
        SELECT @Pid = ProjectId, @Title = Title FROM @ev WHERE Seq = @i;
        EXEC sec.usp_Notification_Raise @NotificationType = 'BUDGET_THRESHOLD', @EntityType = 'PROJECT', @EntityId = @Pid, @Title = @Title;
        SET @i += 1;
    END;

    COMMIT;
END;
