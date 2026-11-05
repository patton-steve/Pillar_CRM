-- Back office > Pricing calculator (Pillar staff, handoff 26): what a month would cost on each plan for the same inputs, side by
-- side, through admin.fn_PlatformBillCalc (the statement's own calculation). One row per active plan (or @PlanCode only); with
-- @TenantId, one row with that tenant's own terms (plan, overrides and contract). Any of the optional term parameters replaces
-- the plan's value for a what-if.
--   Inputs: @MonthlyBilled (pre-tax invoiced in the month), @ExpenseSharePct (0 to 100, the part that is rebilled expenses),
--   @Heads (billable people), @Logins (seats used), @PiloReports.
--   Pillar's cost: card processing on the bill (@ProcessorPct + @ProcessorFixed) and Pilo model cost (@PiloCostPerReport,
--   default: the average cost of a successful Ask Pilo report over the last 90 days, else 0.02).
--   The per-invoice fee cap isn't modelled (it needs each invoice's size).
CREATE PROCEDURE admin.usp_PricingCalculator
    @MonthlyBilled      DECIMAL(19,2),
    @Heads              INT,
    @Logins             INT,
    @ExpenseSharePct    DECIMAL(5,2) = 0,
    @PiloReports        INT = 0,
    @PlanCode           VARCHAR(20) = NULL,
    @TenantId           INT = NULL,
    @FeeRate            DECIMAL(9,6) = NULL,
    @FeePerHeadCap      DECIMAL(19,2) = NULL,
    @MonthlyMinimum     DECIMAL(19,2) = NULL,
    @MonthlyPrice       DECIMAL(19,2) = NULL,
    @IncludedSeats      INT = NULL,
    @ExtraSeatPrice     DECIMAL(19,2) = NULL,
    @DiscountPct        DECIMAL(5,4) = NULL,
    @CommittedSeats     INT = NULL,
    @ProcessorPct       DECIMAL(9,6) = 0.029,
    @ProcessorFixed     DECIMAL(19,2) = 0.30,
    @PiloCostPerReport  DECIMAL(19,6) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF @MonthlyBilled < 0 OR @Heads < 0 OR @Logins < 0 OR @PiloReports < 0 OR @ExpenseSharePct < 0 OR @ExpenseSharePct > 100
        THROW 52631, N'Inputs can''t be negative, and the expense share is 0 to 100.', 1;
    IF @TenantId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    IF @PiloCostPerReport IS NULL
        SELECT @PiloCostPerReport = ISNULL(AVG(CostUsd), 0.02) FROM ai.Generation
        WHERE Feature = 'ASK_REPORT' AND Succeeded = 1 AND CreatedAt >= DATEADD(DAY, -90, SYSUTCDATETIME());

    DECLARE @T TABLE (SortOrder INT, PlanId INT, PlanCode VARCHAR(20), PlanName NVARCHAR(100), FeeRate DECIMAL(9,6), FeePerHeadCap DECIMAL(19,2),
                      MonthlyMinimum DECIMAL(19,2), ExcludeExpenses BIT, MonthlyPrice DECIMAL(19,2), DiscountPct DECIMAL(5,4), IncludedSeats INT,
                      CommittedSeats INT, ExtraSeatPrice DECIMAL(19,2), IncludedReports INT, OveragePrice DECIMAL(19,2), OverageCap DECIMAL(19,2));
    IF @TenantId IS NOT NULL
        INSERT INTO @T
        SELECT 0, t.PlanId, t.PlanCode, t.PlanName, t.FeeRate, t.FeePerHeadCap, t.MonthlyMinimum, t.ExcludeExpensesFromFee, t.MonthlyPrice,
               t.DiscountPct, t.IncludedSeats, t.CommittedSeats, t.ExtraSeatPrice, t.IncludedAiReports, t.AiOveragePrice, t.PiloOverageCap
        FROM admin.fn_TenantTerms(@TenantId, @Today) AS t;
    ELSE
        INSERT INTO @T
        SELECT p.SortOrder, pt.PlanId, pt.PlanCode, pt.PlanName, pt.FeeRate, pt.FeePerHeadCap, pt.MonthlyMinimum, pt.ExcludeExpensesFromFee,
               pt.MonthlyPrice, 0, pt.IncludedSeats, NULL, pt.ExtraSeatPrice, pt.IncludedAiReports, pt.AiOveragePrice, NULL
        FROM admin.[Plan] AS p
        CROSS APPLY admin.fn_PlanTerms(p.Id, @Today) AS pt
        WHERE p.IsActive = 1 AND (@PlanCode IS NULL OR p.Code = @PlanCode);

    UPDATE @T SET FeeRate = COALESCE(@FeeRate, FeeRate), FeePerHeadCap = COALESCE(@FeePerHeadCap, FeePerHeadCap),
                  MonthlyMinimum = COALESCE(@MonthlyMinimum, MonthlyMinimum), MonthlyPrice = COALESCE(@MonthlyPrice, MonthlyPrice),
                  IncludedSeats = COALESCE(@IncludedSeats, IncludedSeats), ExtraSeatPrice = COALESCE(@ExtraSeatPrice, ExtraSeatPrice),
                  DiscountPct = COALESCE(@DiscountPct, DiscountPct), CommittedSeats = COALESCE(@CommittedSeats, CommittedSeats);

    SELECT x.PlanId, x.PlanCode, x.PlanName, x.FeeBase, c.FeeTotal AS FeeBeforeCap, c.Heads, c.FeeCapAmount, c.CapAdjustment, c.FeeAfterCap,
           c.MinimumAdjustment, c.PlanCharge, c.BilledSeats, c.ExtraSeats, c.SeatCharge, c.OverReports, c.PiloCharge, c.Total,
           CONVERT(DECIMAL(9,4), CASE WHEN @MonthlyBilled > 0 THEN c.Total / @MonthlyBilled END) AS EffectivePct,
           k.ProcessorCost, k.PiloCost, CONVERT(DECIMAL(19,2), c.Total - k.ProcessorCost - k.PiloCost) AS Margin
    FROM (SELECT t.*, CONVERT(DECIMAL(19,2), ROUND(@MonthlyBilled * (1 - IIF(t.ExcludeExpenses = 1, @ExpenseSharePct / 100, 0)), 2)) AS FeeBase
          FROM @T AS t) AS x
    CROSS APPLY admin.fn_PlatformBillCalc(ROUND(x.FeeBase * x.FeeRate, 2), @Heads, x.FeePerHeadCap, x.MonthlyMinimum,
                                          ROUND(x.MonthlyPrice * (1 - x.DiscountPct), 2), @Logins, x.IncludedSeats, x.CommittedSeats,
                                          x.ExtraSeatPrice, @PiloReports, x.IncludedReports, x.OveragePrice, x.OverageCap) AS c
    CROSS APPLY (SELECT CONVERT(DECIMAL(19,2), CASE WHEN c.Total > 0 THEN ROUND(c.Total * @ProcessorPct + @ProcessorFixed, 2) ELSE 0 END) AS ProcessorCost,
                        CONVERT(DECIMAL(19,2), ROUND(@PiloReports * @PiloCostPerReport, 2)) AS PiloCost) AS k
    ORDER BY x.SortOrder, x.PlanCode;
END;
