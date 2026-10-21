-- Replaces a FIXED project's billing schedule in one step (and optionally its fixed fee, e.g. after a change order).
-- @Milestones is a JSON array, in billing order:
--   [{"id": 12, "name": "Deposit", "percent": 0.25, "trigger": "DATE", "billDate": "2026-11-01"},
--    {"name": "Design sign-off", "amount": 5000, "trigger": "TASK", "taskId": 345},
--    {"name": "Go-live", "percent": 0.5, "trigger": "MANUAL"}]
-- Each entry gives amount or percent (percent is turned into an amount; rounding pennies go to the last percent entry).
-- Entries with an id update that milestone; un-invoiced milestones left out are removed; invoiced milestones are kept
-- as they are and may not be changed (leave them out or send them unchanged).
-- The schedule (invoiced + new) must total the fixed fee exactly. An empty array with nothing invoiced removes the schedule.
CREATE PROCEDURE crm.usp_ProjectMilestone_Save
    @ProjectId          INT,
    @Milestones         NVARCHAR(MAX),
    @FixedFeeAmount     DECIMAL(19,4) = NULL     -- new fee; NULL keeps the current one
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Fee DECIMAL(19,2), @BillingType VARCHAR(30), @Total DECIMAL(19,2), @Diff DECIMAL(19,2);

    IF @TenantId IS NULL THROW 51111, N'SESSION_CONTEXT TenantId is not set.', 1;
    IF ISJSON(@Milestones) = 0 THROW 51112, N'Milestones must be a JSON array.', 1;

    SELECT @Fee = ROUND(COALESCE(@FixedFeeAmount, p.FixedFeeAmount), 2), @BillingType = bt.SystemCode
    FROM crm.ClientProject AS p WITH (UPDLOCK)
    JOIN lkp.BillingType AS bt ON bt.TenantId = p.TenantId AND bt.Id = p.BillingTypeId
    WHERE p.TenantId = @TenantId AND p.Id = @ProjectId AND p.DeletedAt IS NULL;

    IF @BillingType IS NULL THROW 51113, N'Project not found.', 1;
    IF @BillingType <> 'FIXED' THROW 51114, N'Milestone schedules are for fixed-fee projects.', 1;
    IF @Fee IS NULL OR @Fee <= 0 THROW 51115, N'Set the project''s fixed fee first.', 1;

    CREATE TABLE #m
    (
        Seq INT, Id INT NULL, Name NVARCHAR(200), Amount DECIMAL(19,2) NULL, PercentOfFee DECIMAL(9,6) NULL,
        TriggerType VARCHAR(10), BillDate DATE NULL, TaskId INT NULL
    );
    INSERT INTO #m
    SELECT CAST(j.[key] AS INT) + 1, x.id, x.name, x.amount, x.[percent], UPPER(x.[trigger]), x.billDate, x.taskId
    FROM OPENJSON(@Milestones) AS j
    CROSS APPLY OPENJSON(j.value) WITH (
        id INT, name NVARCHAR(200), amount DECIMAL(19,2), [percent] DECIMAL(9,6), [trigger] VARCHAR(10), billDate DATE, taskId INT
    ) AS x;

    IF EXISTS (SELECT 1 FROM #m WHERE NULLIF(LTRIM(Name), N'') IS NULL OR TriggerType NOT IN ('DATE', 'MANUAL', 'TASK')
                                   OR (Amount IS NULL AND PercentOfFee IS NULL) OR (Amount IS NOT NULL AND PercentOfFee IS NOT NULL))
        THROW 51116, N'Each milestone needs a name, a trigger (DATE, MANUAL or TASK) and either an amount or a percent.', 1;
    IF EXISTS (SELECT 1 FROM #m AS m WHERE m.Id IS NOT NULL AND NOT EXISTS (
                   SELECT 1 FROM crm.ProjectBillingMilestone AS x WHERE x.TenantId = @TenantId AND x.ProjectId = @ProjectId AND x.Id = m.Id))
        THROW 51117, N'A milestone id does not belong to this project.', 1;

    -- percent -> amount; rounding pennies go to the last percent entry
    UPDATE #m SET Amount = ROUND(@Fee * PercentOfFee, 2) WHERE PercentOfFee IS NOT NULL;

    IF EXISTS (SELECT 1 FROM #m AS m
               JOIN crm.ProjectBillingMilestone AS x ON x.TenantId = @TenantId AND x.Id = m.Id
               WHERE x.InvoiceEntryId IS NOT NULL
                 AND (x.Amount <> m.Amount OR x.Name <> m.Name OR x.TriggerType <> m.TriggerType))
        THROW 51118, N'Invoiced milestones cannot be changed. Void the invoice first, or add a new milestone.', 1;

    SELECT @Total = ISNULL(SUM(Amount), 0) FROM #m;
    SELECT @Total += ISNULL(SUM(x.Amount), 0)
    FROM crm.ProjectBillingMilestone AS x
    WHERE x.TenantId = @TenantId AND x.ProjectId = @ProjectId AND x.InvoiceEntryId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM #m AS m WHERE m.Id = x.Id);

    SET @Diff = CASE WHEN @Total = 0 THEN 0 ELSE @Fee - @Total END;   -- 0 = schedule removed
    IF @Diff <> 0 AND ABS(@Diff) <= 0.05 AND EXISTS (SELECT 1 FROM #m WHERE PercentOfFee IS NOT NULL)
    BEGIN
        UPDATE #m SET Amount = Amount + @Diff WHERE Seq = (SELECT MAX(Seq) FROM #m WHERE PercentOfFee IS NOT NULL);
        SET @Diff = 0;
    END;
    IF @Diff <> 0
    BEGIN
        DECLARE @Msg NVARCHAR(200) = CONCAT(N'Milestones total ', FORMAT(@Total, 'N2'), N' but the fixed fee is ', FORMAT(@Fee, 'N2'), N'.');
        THROW 51119, @Msg, 1;
    END;
    IF EXISTS (SELECT 1 FROM #m WHERE Amount <= 0) THROW 51120, N'Every milestone must be more than zero.', 1;

    BEGIN TRAN;

    DELETE x
    FROM crm.ProjectBillingMilestone AS x
    WHERE x.TenantId = @TenantId AND x.ProjectId = @ProjectId AND x.InvoiceEntryId IS NULL
      AND NOT EXISTS (SELECT 1 FROM #m AS m WHERE m.Id = x.Id);

    UPDATE x
    SET Sequence = m.Seq, Name = m.Name, PercentOfFee = m.PercentOfFee, Amount = m.Amount, TriggerType = m.TriggerType,
        BillDate = CASE WHEN m.TriggerType = 'DATE' THEN m.BillDate END,
        TaskId   = CASE WHEN m.TriggerType = 'TASK' THEN m.TaskId END,
        CompletedAt = CASE WHEN m.TriggerType = 'MANUAL' THEN x.CompletedAt END,
        CompletedBy = CASE WHEN m.TriggerType = 'MANUAL' THEN x.CompletedBy END,
        ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.ProjectBillingMilestone AS x
    JOIN #m AS m ON m.Id = x.Id
    WHERE x.TenantId = @TenantId AND x.InvoiceEntryId IS NULL;

    UPDATE x SET Sequence = m.Seq
    FROM crm.ProjectBillingMilestone AS x
    JOIN #m AS m ON m.Id = x.Id
    WHERE x.TenantId = @TenantId AND x.InvoiceEntryId IS NOT NULL;

    INSERT INTO crm.ProjectBillingMilestone (TenantId, ProjectId, Sequence, Name, PercentOfFee, Amount, TriggerType, BillDate, TaskId)
    SELECT @TenantId, @ProjectId, m.Seq, m.Name, m.PercentOfFee, m.Amount, m.TriggerType,
           CASE WHEN m.TriggerType = 'DATE' THEN m.BillDate END,
           CASE WHEN m.TriggerType = 'TASK' THEN m.TaskId END
    FROM #m AS m
    WHERE m.Id IS NULL;

    IF @FixedFeeAmount IS NOT NULL
        UPDATE crm.ClientProject SET FixedFeeAmount = @FixedFeeAmount, ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @ProjectId;

    COMMIT;
END;
