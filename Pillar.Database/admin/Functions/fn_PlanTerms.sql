-- A plan's prices and limits in force on @AsOf (handoff 26): the latest live admin.PlanVersion with EffectiveFrom on or before
-- it, else the admin.[Plan] row itself (a plan with no versions yet). Every bill for a given date reads this, not admin.[Plan].
CREATE FUNCTION admin.fn_PlanTerms (@PlanId INT, @AsOf DATE)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) p.Id AS PlanId, p.Code AS PlanCode, p.Name AS PlanName, v.PlanVersionId, v.EffectiveFrom,
           v.FeeRate, v.PerInvoiceCap, v.MonthlyMinimum, v.FeePerHeadCap, v.ExcludeExpensesFromFee, v.MonthlyPrice,
           v.IncludedSeats, v.ExtraSeatPrice, v.MaxSeats, v.IncludedAiReports, v.AiOveragePrice, v.IncludedAiSearches
    FROM admin.[Plan] AS p
    CROSS APPLY (
        SELECT pv.Id AS PlanVersionId, pv.EffectiveFrom, pv.FeeRate, pv.PerInvoiceCap, pv.MonthlyMinimum, pv.FeePerHeadCap,
               pv.ExcludeExpensesFromFee, pv.MonthlyPrice, pv.IncludedSeats, pv.ExtraSeatPrice, pv.MaxSeats, pv.IncludedAiReports,
               pv.AiOveragePrice, pv.IncludedAiSearches, 0 AS Pri
        FROM admin.PlanVersion AS pv
        WHERE pv.PlanId = p.Id AND pv.CancelledAt IS NULL AND pv.EffectiveFrom <= @AsOf
        UNION ALL
        SELECT NULL, NULL, p.FeeRate, p.PerInvoiceCap, p.MonthlyMinimum, p.FeePerHeadCap, p.ExcludeExpensesFromFee, p.MonthlyPrice,
               p.IncludedSeats, p.ExtraSeatPrice, p.MaxSeats, p.IncludedAiReports, p.AiOveragePrice, p.IncludedAiSearches, 1
    ) AS v
    WHERE p.Id = @PlanId
    ORDER BY v.Pri, v.EffectiveFrom DESC;
