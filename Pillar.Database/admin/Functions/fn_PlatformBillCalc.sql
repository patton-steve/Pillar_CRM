-- The one calculation behind a month's platform bill (handoff 26), shared by admin.usp_PlatformStatement_Generate, the tenant
-- projection and the pricing calculator so they never disagree. Pass the month's quantities and the effective terms:
--   @FeeTotal        the month's fees after the per-invoice cap (fee lines net of reversals)
--   @Heads           billable heads; when there are fees but no heads (fixed-fee work with no time), 1 head is assumed
--   @FeePerHeadCap   NULL = no cap. CapAdjustment (0 or negative) brings the fees down to Heads x cap
--   @MonthlyMinimum  NULL = none (pass NULL in a tenant's first month). Tops up the fees after the cap
--   @PlanCharge      the month's plan charge, already prorated and discounted
--   @PeakSeats, @IncludedSeats (NULL = unlimited), @CommittedSeats (billed at least), @ExtraSeatPrice
--   @Reports, @IncludedReports, @OveragePrice, @OverageCap (NULL = no cap)
CREATE FUNCTION admin.fn_PlatformBillCalc (
    @FeeTotal DECIMAL(19,2), @Heads INT, @FeePerHeadCap DECIMAL(19,2), @MonthlyMinimum DECIMAL(19,2), @PlanCharge DECIMAL(19,2),
    @PeakSeats INT, @IncludedSeats INT, @CommittedSeats INT, @ExtraSeatPrice DECIMAL(19,2),
    @Reports INT, @IncludedReports INT, @OveragePrice DECIMAL(19,2), @OverageCap DECIMAL(19,2))
RETURNS TABLE
AS
RETURN
    SELECT f.FeeTotal, f.Heads, f.FeeCapAmount, f.CapAdjustment, f.FeeAfterCap, m.MinimumAdjustment,
           ISNULL(@PlanCharge, 0) AS PlanCharge,
           s.BilledSeats, s.ExtraSeats, CONVERT(DECIMAL(19,2), s.ExtraSeats * ISNULL(@ExtraSeatPrice, 0)) AS SeatCharge,
           p.OverReports, p.PiloCharge, p.PiloCapped,
           CONVERT(DECIMAL(19,2), f.FeeAfterCap + m.MinimumAdjustment + ISNULL(@PlanCharge, 0)
                                  + s.ExtraSeats * ISNULL(@ExtraSeatPrice, 0) + p.PiloCharge) AS Total
    FROM (
        SELECT c.FeeTotal, c.Heads, c.FeeCapAmount,
               CONVERT(DECIMAL(19,2), CASE WHEN c.FeeCapAmount IS NOT NULL AND c.FeeTotal > c.FeeCapAmount THEN c.FeeCapAmount - c.FeeTotal ELSE 0 END) AS CapAdjustment,
               CONVERT(DECIMAL(19,2), CASE WHEN c.FeeCapAmount IS NOT NULL AND c.FeeTotal > c.FeeCapAmount THEN c.FeeCapAmount ELSE c.FeeTotal END) AS FeeAfterCap
        FROM (SELECT CONVERT(DECIMAL(19,2), ISNULL(@FeeTotal, 0)) AS FeeTotal,
                     CASE WHEN ISNULL(@FeeTotal, 0) > 0 AND ISNULL(@Heads, 0) < 1 THEN 1 ELSE ISNULL(@Heads, 0) END AS Heads,
                     CONVERT(DECIMAL(19,2), @FeePerHeadCap * CASE WHEN ISNULL(@FeeTotal, 0) > 0 AND ISNULL(@Heads, 0) < 1 THEN 1 ELSE ISNULL(@Heads, 0) END) AS FeeCapAmount
             ) AS c
    ) AS f
    CROSS APPLY (SELECT CONVERT(DECIMAL(19,2), CASE WHEN @MonthlyMinimum > 0 AND f.FeeAfterCap < @MonthlyMinimum
                                                    THEN @MonthlyMinimum - CASE WHEN f.FeeAfterCap > 0 THEN f.FeeAfterCap ELSE 0 END
                                                    ELSE 0 END) AS MinimumAdjustment) AS m
    CROSS APPLY (SELECT b.BilledSeats,
                        CASE WHEN @IncludedSeats IS NOT NULL AND b.BilledSeats > @IncludedSeats AND ISNULL(@ExtraSeatPrice, 0) > 0
                             THEN b.BilledSeats - @IncludedSeats ELSE 0 END AS ExtraSeats
                 FROM (SELECT CASE WHEN ISNULL(@CommittedSeats, 0) > ISNULL(@PeakSeats, 0) THEN @CommittedSeats ELSE ISNULL(@PeakSeats, 0) END AS BilledSeats) AS b) AS s
    CROSS APPLY (SELECT r.OverReports,
                        CONVERT(DECIMAL(19,2), CASE WHEN @OverageCap IS NOT NULL AND r.Raw > @OverageCap THEN @OverageCap ELSE r.Raw END) AS PiloCharge,
                        CONVERT(BIT, CASE WHEN @OverageCap IS NOT NULL AND r.Raw > @OverageCap THEN 1 ELSE 0 END) AS PiloCapped
                 FROM (SELECT o.OverReports, CONVERT(DECIMAL(19,2), o.OverReports * ISNULL(@OveragePrice, 0)) AS Raw
                       FROM (SELECT CASE WHEN ISNULL(@OveragePrice, 0) > 0 AND ISNULL(@Reports, 0) > ISNULL(@IncludedReports, 0)
                                         THEN ISNULL(@Reports, 0) - ISNULL(@IncludedReports, 0) ELSE 0 END AS OverReports) AS o) AS r) AS p;
