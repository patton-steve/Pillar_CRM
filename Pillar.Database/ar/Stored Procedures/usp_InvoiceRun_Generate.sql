-- Creates a run of DRAFT invoices from everything billable up to @PeriodEnd (optionally one client or project):
--   * approved, unbilled, billable time on HOURLY and NTE projects -> TIME lines per (project, task, rate)
--   * RETAINER projects -> one RETAINER line per calendar month not yet billed; that month's time links to it as detail
--   * NTE projects -> a negative ADJUSTMENT line when time billed to date would exceed BudgetAmount
--   * approved billable AP bill / expense report lines on any project -> one EXPENSE line each (with markup)
--   * FIXED projects -> one FIXED_FEE line per ready milestone (crm.ProjectBillingMilestone: DATE reached, MANUAL completed,
--     or TASK done, on or before @PeriodEnd)
-- Invoices group by client billing profile + effective payment term (+ project when the profile is PER_PROJECT).
-- Work for profiles without a billing contact, or clients that are not ACTIVE, is skipped and logged in
-- ar.InvoiceRunException. Other lines (DISCOUNT, one-off ADJUSTMENT) are added by hand to drafts.
-- Time entries are linked to draft lines (so the next run won't pick them up) but stay APPROVED until issue.
CREATE PROCEDURE ar.usp_InvoiceRun_Generate
    @PeriodEnd      DATE,
    @ClientId       INT = NULL,
    @ProjectId      INT = NULL,
    @Source         VARCHAR(10) = 'MANUAL',
    @InvoiceRunId   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @TaxRate DECIMAL(9,6), @DraftStatusId INT,
            @TimeTypeId INT, @RetainerTypeId INT, @AdjTypeId INT, @ExpenseTypeId INT, @FixedTypeId INT,
            @MonthStart DATE = DATEFROMPARTS(YEAR(@PeriodEnd), MONTH(@PeriodEnd), 1);

    IF @TenantId IS NULL THROW 50601, N'SESSION_CONTEXT TenantId is not set.', 1;
    IF @PeriodEnd IS NULL THROW 50602, N'Period end is required.', 1;

    SELECT @TaxRate = ISNULL(TRY_CAST(Value AS DECIMAL(9,6)), 0) FROM admin.fn_Setting(@TenantId, NULL, 'Invoice.DefaultTaxRate');
    SELECT @DraftStatusId = Id FROM lkp.InvoiceStatus WHERE TenantId = @TenantId AND SystemCode = 'DRAFT';
    SELECT @TimeTypeId = Id FROM lkp.InvoiceLineType WHERE TenantId = @TenantId AND SystemCode = 'TIME';
    SELECT @RetainerTypeId = Id FROM lkp.InvoiceLineType WHERE TenantId = @TenantId AND SystemCode = 'RETAINER';
    SELECT @AdjTypeId = Id FROM lkp.InvoiceLineType WHERE TenantId = @TenantId AND SystemCode = 'ADJUSTMENT';
    SELECT @ExpenseTypeId = Id FROM lkp.InvoiceLineType WHERE TenantId = @TenantId AND SystemCode = 'EXPENSE';
    SELECT @FixedTypeId = Id FROM lkp.InvoiceLineType WHERE TenantId = @TenantId AND SystemCode = 'FIXED_FEE';

    ------------------------------------------------------------ candidate projects
    CREATE TABLE #proj
    (
        ProjectId INT PRIMARY KEY, ClientId INT, BillingProfileId INT, TermId INT, GroupProjectId INT,
        BillingType VARCHAR(30), FixedFeeAmount DECIMAL(19,4), BudgetAmount DECIMAL(19,4), Name NVARCHAR(200),
        StartDate DATE, EndDate DATE, ProjectStatus VARCHAR(30), Skip VARCHAR(30) NULL
    );

    INSERT INTO #proj
    SELECT p.Id, p.ClientId, p.BillingProfileId, COALESCE(p.PaymentTermId, bp.PaymentTermId),
           CASE WHEN bp.InvoiceGrouping = 'PER_PROJECT' THEN p.Id END,
           bt.SystemCode, p.FixedFeeAmount, p.BudgetAmount, p.Name, p.StartDate, p.EndDate, ps.SystemCode,
           CASE WHEN cs.SystemCode <> 'ACTIVE' THEN 'CLIENT_NOT_ACTIVE'
                WHEN bp.BillingContactId IS NULL THEN 'NO_BILLING_CONTACT' END
    FROM crm.ClientProject AS p
    JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = p.TenantId AND bp.Id = p.BillingProfileId
    JOIN lkp.BillingType AS bt ON bt.TenantId = p.TenantId AND bt.Id = p.BillingTypeId
    JOIN lkp.ProjectStatus AS ps ON ps.TenantId = p.TenantId AND ps.Id = p.ProjectStatusId
    JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
    JOIN lkp.ClientStatus AS cs ON cs.TenantId = c.TenantId AND cs.Id = c.ClientStatusId
    WHERE p.TenantId = @TenantId AND p.DeletedAt IS NULL
      AND bt.SystemCode IN ('HOURLY', 'NTE', 'RETAINER', 'FIXED')   -- FIXED: milestones and rebilled expenses only
      AND (@ClientId IS NULL OR p.ClientId = @ClientId)
      AND (@ProjectId IS NULL OR p.Id = @ProjectId);

    ------------------------------------------------------------ billable time
    CREATE TABLE #time
    (
        TimeEntryId INT PRIMARY KEY, ProjectId INT, TaskId INT, WorkDate DATE,
        BilledMinutes INT, RateApplied DECIMAL(19,4), AmountBillable DECIMAL(19,2)
    );

    INSERT INTO #time
    SELECT e.Id, e.ProjectId, e.TaskId, e.WorkDate, e.BilledMinutes, ISNULL(e.RateApplied, 0), e.AmountBillable
    FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId AND s.SystemCode = 'APPROVED'
    JOIN #proj AS p ON p.ProjectId = e.ProjectId AND p.BillingType IN ('HOURLY', 'NTE', 'RETAINER')
    WHERE e.TenantId = @TenantId AND e.DeletedAt IS NULL AND e.InvoiceEntryId IS NULL
      AND e.IsBillable = 1 AND e.WorkDate <= @PeriodEnd;

    ------------------------------------------------------------ billable expenses from approved AP bills
    CREATE TABLE #exp (BillLineId INT PRIMARY KEY, ProjectId INT, TaskId INT, Description NVARCHAR(1000), Amount DECIMAL(19,2));

    INSERT INTO #exp
    SELECT bl.Id, bl.ProjectId, bl.TaskId, ec.Name + N': ' + bl.Description, bl.BillableAmount
    FROM ap.BillLine AS bl
    JOIN ap.Bill AS b ON b.TenantId = bl.TenantId AND b.Id = bl.BillId
    JOIN lkp.BillStatus AS bs ON bs.TenantId = b.TenantId AND bs.Id = b.BillStatusId AND bs.SystemCode IN ('OPEN', 'PARTIAL', 'PAID')
    JOIN lkp.ExpenseCategory AS ec ON ec.TenantId = bl.TenantId AND ec.Id = bl.ExpenseCategoryId
    JOIN #proj AS p ON p.ProjectId = bl.ProjectId
    WHERE bl.TenantId = @TenantId AND bl.IsBillable = 1 AND bl.InvoiceEntryId IS NULL
      AND COALESCE(bl.ExpenseDate, b.BillDate) <= @PeriodEnd;

    ------------------------------------------------------------ fixed-fee milestones ready to bill
    CREATE TABLE #ms (MilestoneId INT PRIMARY KEY, ProjectId INT, TaskId INT, Sequence INT, Description NVARCHAR(1000), Amount DECIMAL(19,2));

    INSERT INTO #ms
    SELECT m.Id, m.ProjectId, m.TaskId, m.Sequence, p.Name + N': ' + m.Name, m.Amount
    FROM crm.ProjectBillingMilestone AS m
    JOIN #proj AS p ON p.ProjectId = m.ProjectId AND p.BillingType = 'FIXED' AND p.ProjectStatus <> 'PLANNED'
    LEFT JOIN crm.ClientTask AS t ON t.TenantId = m.TenantId AND t.Id = m.TaskId
    WHERE m.TenantId = @TenantId AND m.InvoiceEntryId IS NULL
      AND (   (m.TriggerType = 'DATE'   AND m.BillDate <= @PeriodEnd)
           OR (m.TriggerType = 'MANUAL' AND CAST(m.CompletedAt AS DATE) <= @PeriodEnd)
           OR (m.TriggerType = 'TASK'   AND CAST(t.CompletedAt AS DATE) <= @PeriodEnd AND t.DeletedAt IS NULL));

    ------------------------------------------------------------ retainers due this month
    CREATE TABLE #retainer (ProjectId INT PRIMARY KEY, Amount DECIMAL(19,2));

    INSERT INTO #retainer
    SELECT p.ProjectId, ROUND(p.FixedFeeAmount, 2)
    FROM #proj AS p
    WHERE p.BillingType = 'RETAINER' AND p.ProjectStatus <> 'PLANNED'
      AND (p.StartDate IS NULL OR p.StartDate <= @PeriodEnd)
      AND (p.EndDate IS NULL OR p.EndDate >= @MonthStart)
      AND NOT EXISTS (
          SELECT 1
          FROM ar.InvoiceEntry AS l
          JOIN ar.Invoice AS i ON i.TenantId = l.TenantId AND i.Id = l.InvoiceId
          JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId
          WHERE l.TenantId = @TenantId AND l.ProjectId = p.ProjectId AND l.LineTypeId = @RetainerTypeId
            AND l.ServicePeriodStart = @MonthStart AND st.SystemCode <> 'VOID');

    -- retainer time only bills as detail under a retainer line in this run
    DELETE t FROM #time AS t
    JOIN #proj AS p ON p.ProjectId = t.ProjectId
    WHERE p.BillingType = 'RETAINER'
      AND (NOT EXISTS (SELECT 1 FROM #retainer AS r WHERE r.ProjectId = t.ProjectId) OR t.WorkDate < @MonthStart);

    BEGIN TRAN;

    INSERT INTO ar.InvoiceRun (TenantId, PeriodEnd, ClientId, ProjectId, Source)
    VALUES (@TenantId, @PeriodEnd, @ClientId, @ProjectId, @Source);
    SET @InvoiceRunId = SCOPE_IDENTITY();

    ------------------------------------------------------------ exceptions
    INSERT INTO ar.InvoiceRunException (TenantId, InvoiceRunId, ClientId, BillingProfileId, ProjectId, Reason, Message)
    SELECT @TenantId, @InvoiceRunId, p.ClientId, p.BillingProfileId, p.ProjectId, p.Skip,
           CASE p.Skip WHEN 'NO_BILLING_CONTACT' THEN N'Billing profile has no billing contact: ' + p.Name
                       ELSE N'Client is not active: ' + p.Name END
    FROM #proj AS p
    WHERE p.Skip IS NOT NULL
      AND (EXISTS (SELECT 1 FROM #time AS t WHERE t.ProjectId = p.ProjectId)
           OR EXISTS (SELECT 1 FROM #retainer AS r WHERE r.ProjectId = p.ProjectId)
           OR EXISTS (SELECT 1 FROM #exp AS x WHERE x.ProjectId = p.ProjectId)
           OR EXISTS (SELECT 1 FROM #ms AS m WHERE m.ProjectId = p.ProjectId));

    DELETE t FROM #time AS t JOIN #proj AS p ON p.ProjectId = t.ProjectId WHERE p.Skip IS NOT NULL;
    DELETE r FROM #retainer AS r JOIN #proj AS p ON p.ProjectId = r.ProjectId WHERE p.Skip IS NOT NULL;
    DELETE x FROM #exp AS x JOIN #proj AS p ON p.ProjectId = x.ProjectId WHERE p.Skip IS NOT NULL;
    DELETE m FROM #ms AS m JOIN #proj AS p ON p.ProjectId = m.ProjectId WHERE p.Skip IS NOT NULL;

    ------------------------------------------------------------ one draft per group
    CREATE TABLE #inv (InvoiceId INT, ClientId INT, BillingProfileId INT, TermId INT, GroupProjectId INT);

    MERGE ar.Invoice AS tgt
    USING (
        SELECT DISTINCT p.ClientId, p.BillingProfileId, p.TermId, p.GroupProjectId, bp.TaxExempt
        FROM #proj AS p
        JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = @TenantId AND bp.Id = p.BillingProfileId
        WHERE EXISTS (SELECT 1 FROM #time AS t WHERE t.ProjectId = p.ProjectId)
           OR EXISTS (SELECT 1 FROM #retainer AS r WHERE r.ProjectId = p.ProjectId)
           OR EXISTS (SELECT 1 FROM #exp AS x WHERE x.ProjectId = p.ProjectId)
           OR EXISTS (SELECT 1 FROM #ms AS m WHERE m.ProjectId = p.ProjectId)
    ) AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (TenantId, ClientId, BillingProfileId, InvoiceRunId, InvoiceStatusId, PaymentTermId, PeriodEnd, TaxRate, TaxExempt)
        VALUES (@TenantId, src.ClientId, src.BillingProfileId, @InvoiceRunId, @DraftStatusId, src.TermId, @PeriodEnd, @TaxRate, src.TaxExempt)
    OUTPUT inserted.Id, src.ClientId, src.BillingProfileId, src.TermId, src.GroupProjectId INTO #inv;

    ------------------------------------------------------------ lines
    CREATE TABLE #line
    (
        InvoiceId INT, LineTypeId INT, SortGroup INT, ProjectId INT, TaskId INT, Rate DECIMAL(19,4),
        Description NVARCHAR(1000), Quantity DECIMAL(19,4), UnitPrice DECIMAL(19,4), Amount DECIMAL(19,2),
        ServicePeriodStart DATE, ServicePeriodEnd DATE, InvoiceEntryId INT NULL, BillLineId INT NULL,
        MilestoneId INT NULL, MilestoneSeq INT NULL
    );

    -- TIME: one line per project, task and rate
    INSERT INTO #line (InvoiceId, LineTypeId, SortGroup, ProjectId, TaskId, Rate, Description, Quantity, UnitPrice, Amount)
    SELECT i.InvoiceId, @TimeTypeId, 1, t.ProjectId, t.TaskId, t.RateApplied,
           tk.TaskKey + N' ' + tk.Title,
           SUM(t.BilledMinutes) / 60.0, t.RateApplied, SUM(t.AmountBillable)
    FROM #time AS t
    JOIN #proj AS p ON p.ProjectId = t.ProjectId AND p.BillingType <> 'RETAINER'
    JOIN #inv AS i ON i.BillingProfileId = p.BillingProfileId AND i.TermId = p.TermId
                  AND (i.GroupProjectId = p.GroupProjectId OR (i.GroupProjectId IS NULL AND p.GroupProjectId IS NULL))
    JOIN crm.ClientTask AS tk ON tk.TenantId = @TenantId AND tk.Id = t.TaskId
    GROUP BY i.InvoiceId, t.ProjectId, t.TaskId, t.RateApplied, tk.TaskKey, tk.Title;

    -- RETAINER: one line per project for the month
    INSERT INTO #line (InvoiceId, LineTypeId, SortGroup, ProjectId, Description, Quantity, UnitPrice, Amount, ServicePeriodStart, ServicePeriodEnd)
    SELECT i.InvoiceId, @RetainerTypeId, 0, r.ProjectId,
           p.Name + N' retainer, ' + FORMAT(@MonthStart, 'MMMM yyyy', 'en-US'),
           1, r.Amount, r.Amount, @MonthStart, EOMONTH(@MonthStart)
    FROM #retainer AS r
    JOIN #proj AS p ON p.ProjectId = r.ProjectId
    JOIN #inv AS i ON i.BillingProfileId = p.BillingProfileId AND i.TermId = p.TermId
                  AND (i.GroupProjectId = p.GroupProjectId OR (i.GroupProjectId IS NULL AND p.GroupProjectId IS NULL));

    -- EXPENSE: one line per rebilled bill line
    INSERT INTO #line (InvoiceId, LineTypeId, SortGroup, ProjectId, TaskId, Description, Quantity, UnitPrice, Amount, BillLineId)
    SELECT i.InvoiceId, @ExpenseTypeId, 3, x.ProjectId, x.TaskId, x.Description, 1, x.Amount, x.Amount, x.BillLineId
    FROM #exp AS x
    JOIN #proj AS p ON p.ProjectId = x.ProjectId
    JOIN #inv AS i ON i.BillingProfileId = p.BillingProfileId AND i.TermId = p.TermId
                  AND (i.GroupProjectId = p.GroupProjectId OR (i.GroupProjectId IS NULL AND p.GroupProjectId IS NULL));

    -- FIXED_FEE: one line per ready milestone, in schedule order
    INSERT INTO #line (InvoiceId, LineTypeId, SortGroup, ProjectId, TaskId, Description, Quantity, UnitPrice, Amount, MilestoneId, MilestoneSeq)
    SELECT i.InvoiceId, @FixedTypeId, 0, m.ProjectId, m.TaskId, m.Description, 1, m.Amount, m.Amount, m.MilestoneId, m.Sequence
    FROM #ms AS m
    JOIN #proj AS p ON p.ProjectId = m.ProjectId
    JOIN #inv AS i ON i.BillingProfileId = p.BillingProfileId AND i.TermId = p.TermId
                  AND (i.GroupProjectId = p.GroupProjectId OR (i.GroupProjectId IS NULL AND p.GroupProjectId IS NULL));

    -- NTE: cap time billed to date (issued or draft, not void) at BudgetAmount; expenses are outside the cap
    INSERT INTO #line (InvoiceId, LineTypeId, SortGroup, ProjectId, Description, Quantity, UnitPrice, Amount)
    SELECT x.InvoiceId, @AdjTypeId, 2, x.ProjectId,
           p.Name + N' not-to-exceed limit applied', 1, -x.Excess, -x.Excess
    FROM (
        SELECT l.InvoiceId, l.ProjectId,
               ISNULL(prior.Billed, 0) + SUM(l.Amount) - MAX(p.BudgetAmount) AS Excess
        FROM #line AS l
        JOIN #proj AS p ON p.ProjectId = l.ProjectId AND p.BillingType = 'NTE' AND l.LineTypeId = @TimeTypeId
        OUTER APPLY (
            SELECT SUM(e.Amount) AS Billed
            FROM ar.InvoiceEntry AS e
            JOIN ar.Invoice AS i ON i.TenantId = e.TenantId AND i.Id = e.InvoiceId
            JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId
            WHERE e.TenantId = @TenantId AND e.ProjectId = l.ProjectId AND st.SystemCode <> 'VOID'
              AND e.LineTypeId IN (@TimeTypeId, @AdjTypeId)
        ) AS prior
        GROUP BY l.InvoiceId, l.ProjectId, prior.Billed
    ) AS x
    JOIN #proj AS p ON p.ProjectId = x.ProjectId
    WHERE x.Excess > 0;
    -- if prior billing already exceeded the budget, the adjustment cancels only this run's amount
    UPDATE l SET Amount = -t.ThisRun, UnitPrice = -t.ThisRun
    FROM #line AS l
    JOIN (SELECT InvoiceId, ProjectId, SUM(Amount) AS ThisRun FROM #line WHERE LineTypeId = @TimeTypeId GROUP BY InvoiceId, ProjectId) AS t
      ON t.InvoiceId = l.InvoiceId AND t.ProjectId = l.ProjectId
    WHERE l.LineTypeId = @AdjTypeId AND -l.Amount > t.ThisRun;

    -- write lines, capturing ids for the time links
    CREATE TABLE #lineIds (InvoiceEntryId INT, InvoiceId INT, LineTypeId INT, ProjectId INT, TaskId INT, Rate DECIMAL(19,4), BillLineId INT, MilestoneId INT);
    MERGE ar.InvoiceEntry AS tgt
    USING (
        SELECT l.*, ROW_NUMBER() OVER (PARTITION BY l.InvoiceId ORDER BY l.ProjectId, l.SortGroup, l.MilestoneSeq, l.TaskId, l.Rate) AS LineNumber
        FROM #line AS l
    ) AS src
    ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (TenantId, InvoiceId, LineNumber, LineTypeId, ProjectId, TaskId, Description, Quantity, UnitPrice, Amount,
                ServicePeriodStart, ServicePeriodEnd)
        VALUES (@TenantId, src.InvoiceId, src.LineNumber, src.LineTypeId, src.ProjectId, src.TaskId, src.Description,
                src.Quantity, src.UnitPrice, src.Amount, src.ServicePeriodStart, src.ServicePeriodEnd)
    OUTPUT inserted.Id, src.InvoiceId, src.LineTypeId, src.ProjectId, src.TaskId, src.Rate, src.BillLineId, src.MilestoneId
    INTO #lineIds (InvoiceEntryId, InvoiceId, LineTypeId, ProjectId, TaskId, Rate, BillLineId, MilestoneId);

    -- link time to its line (retainer time to the retainer line)
    UPDATE e
    SET InvoiceEntryId = li.InvoiceEntryId
    FROM crm.TimeEntry AS e
    JOIN #time AS t ON t.TimeEntryId = e.Id
    JOIN #proj AS p ON p.ProjectId = t.ProjectId
    JOIN #lineIds AS li ON li.ProjectId = t.ProjectId
                       AND ((p.BillingType = 'RETAINER' AND li.LineTypeId = @RetainerTypeId)
                         OR (p.BillingType <> 'RETAINER' AND li.LineTypeId = @TimeTypeId AND li.TaskId = t.TaskId AND li.Rate = t.RateApplied))
    WHERE e.TenantId = @TenantId;

    UPDATE bl
    SET InvoiceEntryId = li.InvoiceEntryId
    FROM ap.BillLine AS bl
    JOIN #lineIds AS li ON li.BillLineId = bl.Id
    WHERE bl.TenantId = @TenantId;

    UPDATE m
    SET InvoiceEntryId = li.InvoiceEntryId
    FROM crm.ProjectBillingMilestone AS m
    JOIN #lineIds AS li ON li.MilestoneId = m.Id
    WHERE m.TenantId = @TenantId;

    ------------------------------------------------------------ totals
    UPDATE i
    SET SubTotal  = l.SubTotal,
        TaxAmount = CASE WHEN i.TaxExempt = 1 THEN 0 ELSE ROUND(l.Taxable * i.TaxRate, 2) END,
        PeriodStart = l.PeriodStart
    FROM ar.Invoice AS i
    JOIN (
        SELECT e.InvoiceId, SUM(e.Amount) AS SubTotal, SUM(CASE WHEN e.IsTaxable = 1 THEN e.Amount ELSE 0 END) AS Taxable,
               (SELECT MIN(t.WorkDate) FROM crm.TimeEntry AS t
                JOIN ar.InvoiceEntry AS x ON x.TenantId = t.TenantId AND x.Id = t.InvoiceEntryId
                WHERE x.InvoiceId = e.InvoiceId AND t.TenantId = @TenantId) AS PeriodStart
        FROM ar.InvoiceEntry AS e
        WHERE e.TenantId = @TenantId AND e.InvoiceId IN (SELECT InvoiceId FROM #inv)
        GROUP BY e.InvoiceId
    ) AS l ON l.InvoiceId = i.Id
    WHERE i.TenantId = @TenantId;

    UPDATE ar.InvoiceRun
    SET InvoiceCount   = (SELECT COUNT(*) FROM #inv),
        ExceptionCount = (SELECT COUNT(*) FROM ar.InvoiceRunException WHERE TenantId = @TenantId AND InvoiceRunId = @InvoiceRunId)
    WHERE TenantId = @TenantId AND Id = @InvoiceRunId;

    COMMIT;
END;
