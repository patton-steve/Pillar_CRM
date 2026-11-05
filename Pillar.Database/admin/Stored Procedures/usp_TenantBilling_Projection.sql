-- This month's platform bill for one tenant (Pillar staff, handoff 26): the Contract & billing tab's Projection. Two result sets:
--   1. one row per scenario, each through admin.fn_PlatformBillCalc (the statement's own calculation):
--        MONTH_TO_DATE   real data so far: fees accrued this month, billable heads so far, the month's peak seats, Pilo reports,
--                        and the plan prorated to the days gone
--        PROJECTED       month end at the current run rate: fees and Pilo reports scaled to the whole month, heads and seats as now,
--                        the full month's plan
--        PROJECTED_AFTER only with @OverrideKey: PROJECTED again with that override set to @OverrideValue (NULL = cleared), the
--                        "before / after" shown before saving. A fee rate or expense change recomputes the fees from their base
--                        (the per-invoice cap is not reapplied).
--      Columns: InvoicedSubtotal (issued this month), FeeBase, the calculation's columns, and EffectivePct (Total / InvoicedSubtotal).
--   2. the last 6 statements.
CREATE PROCEDURE admin.usp_TenantBilling_Projection
    @TenantId       INT,
    @OverrideKey    VARCHAR(100) = NULL,
    @OverrideValue  NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;
    IF @OverrideKey IS NOT NULL AND @OverrideKey NOT IN ('Platform.FeeRateOverride', 'Platform.FeePerHeadCapOverride',
        'Platform.MonthlyMinimumOverride', 'Platform.ExcludeExpensesOverride', 'Plan.MonthlyPriceOverride', 'Seats.IncludedOverride',
        'Seats.ExtraPriceOverride', 'Pilo.MonthlyReportsOverride')
        THROW 52630, N'That override can''t be previewed here.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @Month DATE = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);
    DECLARE @From DATETIME2(0) = CAST(@Month AS DATETIME2(0)), @To DATETIME2(0) = DATEADD(MONTH, 1, CAST(@Month AS DATETIME2(0))),
            @Dim INT = DAY(EOMONTH(@Month)), @Elapsed INT = DAY(@Today);

    DECLARE @FeeRate DECIMAL(9,6), @HeadCap DECIMAL(19,2), @Minimum DECIMAL(19,2), @Exclude BIT, @Price DECIMAL(19,2), @Discount DECIMAL(5,4),
            @Included INT, @Committed INT, @SeatPrice DECIMAL(19,2), @IncludedReports INT, @ReportPrice DECIMAL(19,2), @PiloCap DECIMAL(19,2),
            @FirstMonth BIT;
    SELECT @FeeRate = t.FeeRate, @HeadCap = t.FeePerHeadCap, @Minimum = t.MonthlyMinimum, @Exclude = t.ExcludeExpensesFromFee,
           @Price = t.MonthlyPrice, @Discount = t.DiscountPct, @Included = t.IncludedSeats, @Committed = t.CommittedSeats,
           @SeatPrice = t.ExtraSeatPrice, @IncludedReports = t.IncludedAiReports, @ReportPrice = t.AiOveragePrice, @PiloCap = t.PiloOverageCap
    FROM admin.fn_TenantTerms(@TenantId, @Today) AS t;
    SELECT @FirstMonth = IIF(CreatedAt >= @From, 1, 0) FROM admin.Tenant WHERE Id = @TenantId;

    DECLARE @Fees DECIMAL(19,2), @Base DECIMAL(19,2), @Expenses DECIMAL(19,2), @Invoiced DECIMAL(19,2), @Heads INT, @Peak INT, @Reports INT;
    SELECT @Fees = ISNULL(SUM(f.FeeAmount), 0), @Base = ISNULL(SUM(f.FeeBaseAmount), 0)
    FROM admin.PlatformFee AS f WHERE f.TenantId = @TenantId AND f.AccruedAt >= @From AND f.AccruedAt < @To;
    SELECT @Invoiced = ISNULL(SUM(i.SubTotal), 0),
           @Expenses = ISNULL(SUM(x.Amount), 0)
    FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.Id = i.InvoiceStatusId AND st.SystemCode <> 'VOID' AND st.SystemCode <> 'DRAFT'
    OUTER APPLY (SELECT SUM(e.Amount) AS Amount FROM ar.InvoiceEntry AS e
                 JOIN lkp.InvoiceLineType AS lt ON lt.TenantId = e.TenantId AND lt.Id = e.LineTypeId AND lt.SystemCode = 'EXPENSE'
                 WHERE e.TenantId = i.TenantId AND e.InvoiceId = i.Id) AS x
    WHERE i.TenantId = @TenantId AND i.IssuedAt >= @From AND i.IssuedAt < @To;
    SELECT @Heads = Heads FROM admin.fn_BillableHeads(@TenantId, @Month);
    SELECT @Peak = MAX(PeakSeats) FROM admin.TenantSeatDaily WHERE TenantId = @TenantId AND SeatDate >= @Month AND SeatDate <= @Today;
    IF @Peak IS NULL SELECT @Peak = UsedSeats FROM admin.fn_TenantSeats(@TenantId);
    SELECT @Reports = COUNT(*) FROM ai.Generation WHERE TenantId = @TenantId AND CountsTowardQuota = 1 AND CreatedAt >= @From AND CreatedAt < @To;

    DECLARE @S TABLE (Sort INT, Scenario VARCHAR(20), Invoiced DECIMAL(19,2), FeeBase DECIMAL(19,2), Fees DECIMAL(19,2), Heads INT,
                      HeadCap DECIMAL(19,2), Minimum DECIMAL(19,2), PlanCharge DECIMAL(19,2), Peak INT, Included INT, Committed INT,
                      SeatPrice DECIMAL(19,2), Reports INT, IncludedReports INT);
    INSERT INTO @S VALUES
        (1, 'MONTH_TO_DATE', @Invoiced, @Base, @Fees, @Heads, @HeadCap, IIF(@FirstMonth = 1, NULL, @Minimum),
            ROUND(ROUND(@Price * @Elapsed / @Dim, 2) * (1 - @Discount), 2), @Peak, @Included, @Committed, @SeatPrice, @Reports, @IncludedReports),
        (2, 'PROJECTED', ROUND(@Invoiced * @Dim / @Elapsed, 2), ROUND(@Base * @Dim / @Elapsed, 2), ROUND(@Fees * @Dim / @Elapsed, 2), @Heads,
            @HeadCap, IIF(@FirstMonth = 1, NULL, @Minimum), ROUND(@Price * (1 - @Discount), 2), @Peak, @Included, @Committed, @SeatPrice,
            CEILING(@Reports * 1.0 * @Dim / @Elapsed), @IncludedReports);

    IF @OverrideKey IS NOT NULL
    BEGIN
        DECLARE @NewRate DECIMAL(9,6) = @FeeRate, @NewExclude BIT = @Exclude, @PlanFull DECIMAL(19,2), @NewBase DECIMAL(19,2), @ProjBase DECIMAL(19,2),
                @ProjExp DECIMAL(19,2) = ROUND(@Expenses * @Dim / @Elapsed, 2);
        SELECT @ProjBase = FeeBase FROM @S WHERE Sort = 2;
        INSERT INTO @S SELECT 3, 'PROJECTED_AFTER', Invoiced, FeeBase, Fees, Heads, HeadCap, Minimum, PlanCharge, Peak, Included, Committed,
                              SeatPrice, Reports, IncludedReports FROM @S WHERE Sort = 2;
        -- the plan's own value when the override is cleared
        DECLARE @PlanId INT; SELECT @PlanId = PlanId FROM admin.fn_TenantPlanOn(@TenantId, @Today);
        IF @OverrideKey = 'Platform.FeeRateOverride'
            SELECT @NewRate = COALESCE(TRY_CONVERT(DECIMAL(9,6), @OverrideValue), FeeRate) FROM admin.fn_PlanTerms(@PlanId, @Today);
        IF @OverrideKey = 'Platform.ExcludeExpensesOverride'
            SELECT @NewExclude = COALESCE(TRY_CONVERT(BIT, @OverrideValue), ExcludeExpensesFromFee) FROM admin.fn_PlanTerms(@PlanId, @Today);
        IF @OverrideKey IN ('Platform.FeeRateOverride', 'Platform.ExcludeExpensesOverride')
        BEGIN
            SET @NewBase = @ProjBase + CASE WHEN @Exclude = 1 AND @NewExclude = 0 THEN @ProjExp WHEN @Exclude = 0 AND @NewExclude = 1 THEN -@ProjExp ELSE 0 END;
            UPDATE @S SET FeeBase = @NewBase, Fees = ROUND(@NewBase * @NewRate, 2) WHERE Sort = 3;
        END;
        IF @OverrideKey = 'Platform.FeePerHeadCapOverride'
            UPDATE s SET HeadCap = COALESCE(TRY_CONVERT(DECIMAL(19,2), @OverrideValue), pt.FeePerHeadCap) FROM @S AS s CROSS JOIN admin.fn_PlanTerms(@PlanId, @Today) AS pt WHERE s.Sort = 3;
        IF @OverrideKey = 'Platform.MonthlyMinimumOverride' AND @FirstMonth = 0
            UPDATE s SET Minimum = COALESCE(TRY_CONVERT(DECIMAL(19,2), @OverrideValue), pt.MonthlyMinimum) FROM @S AS s CROSS JOIN admin.fn_PlanTerms(@PlanId, @Today) AS pt WHERE s.Sort = 3;
        IF @OverrideKey = 'Plan.MonthlyPriceOverride'
            UPDATE s SET PlanCharge = ROUND(COALESCE(TRY_CONVERT(DECIMAL(19,2), @OverrideValue), pt.MonthlyPrice) * (1 - @Discount), 2)
            FROM @S AS s CROSS JOIN admin.fn_PlanTerms(@PlanId, @Today) AS pt WHERE s.Sort = 3;
        IF @OverrideKey = 'Seats.IncludedOverride'
            UPDATE s SET Included = COALESCE(TRY_CONVERT(INT, @OverrideValue), pt.IncludedSeats) FROM @S AS s CROSS JOIN admin.fn_PlanTerms(@PlanId, @Today) AS pt WHERE s.Sort = 3;
        IF @OverrideKey = 'Seats.ExtraPriceOverride'
            UPDATE s SET SeatPrice = COALESCE(TRY_CONVERT(DECIMAL(19,2), @OverrideValue), pt.ExtraSeatPrice) FROM @S AS s CROSS JOIN admin.fn_PlanTerms(@PlanId, @Today) AS pt WHERE s.Sort = 3;
        IF @OverrideKey = 'Pilo.MonthlyReportsOverride'
            UPDATE s SET IncludedReports = COALESCE(TRY_CONVERT(INT, @OverrideValue), pt.IncludedAiReports) FROM @S AS s CROSS JOIN admin.fn_PlanTerms(@PlanId, @Today) AS pt WHERE s.Sort = 3;
    END;

    SELECT s.Scenario, s.Invoiced AS InvoicedSubtotal, s.FeeBase, c.FeeTotal, c.Heads, c.FeeCapAmount, c.CapAdjustment, c.FeeAfterCap,
           c.MinimumAdjustment, c.PlanCharge, c.BilledSeats, c.ExtraSeats, c.SeatCharge, c.OverReports, c.PiloCharge, c.PiloCapped, c.Total,
           CONVERT(DECIMAL(9,4), CASE WHEN s.Invoiced > 0 THEN c.Total / s.Invoiced END) AS EffectivePct
    FROM @S AS s
    CROSS APPLY admin.fn_PlatformBillCalc(s.Fees, s.Heads, s.HeadCap, s.Minimum, s.PlanCharge, s.Peak, s.Included, s.Committed, s.SeatPrice,
                                          s.Reports, s.IncludedReports, @ReportPrice, @PiloCap) AS c
    ORDER BY s.Sort;

    SELECT TOP (6) s.Id AS StatementId, s.PublicId, s.StatementNumber, s.PeriodStart, s.Status, s.FeeTotal, s.CapAdjustment, s.MinimumAdjustment,
           s.SubscriptionTotal, s.ServiceTotal, s.CreditApplied, s.AmountDue, s.AmountPaid, s.BalanceDue, s.BillableHeads
    FROM admin.PlatformStatement AS s
    WHERE s.TenantId = @TenantId AND s.Status <> 'VOID'
    ORDER BY s.PeriodStart DESC;
END;
