-- Everything a tenant is billed by on @AsOf (handoff 26): its plan's terms that day (admin.fn_PlanTerms), its Pillar-only
-- overrides that day (admin.fn_OverrideAsOf) and its contract that day (admin.TenantContract). Plan* columns are the plan's
-- values, Override* the override (NULL = none) and the plain columns the effective value. The statement, the fee at issue,
-- the Contract & billing tab and the pricing calculator all read this, so they never disagree.
--   Overrides: Platform.FeeRateOverride, Platform.FeeCapOverride (per invoice), Platform.MonthlyMinimumOverride,
--   Platform.FeePerHeadCapOverride, Platform.ExcludeExpensesOverride, Plan.MonthlyPriceOverride, Seats.IncludedOverride,
--   Seats.ExtraPriceOverride, Tenant.MaxUsers (the max seats override), Pilo.MonthlyReportsOverride, Pilo.MonthlySearchesOverride.
--   PiloOverageCap is the tenant's own Pilo.OverageCapAmount setting (current value).
CREATE FUNCTION admin.fn_TenantTerms (@TenantId INT, @AsOf DATE)
RETURNS TABLE
AS
RETURN
    SELECT pt.PlanId, pt.PlanCode, pt.PlanName, pt.PlanVersionId,
           -- plan values
           pt.FeeRate AS PlanFeeRate, pt.PerInvoiceCap AS PlanPerInvoiceCap, pt.MonthlyMinimum AS PlanMonthlyMinimum,
           pt.FeePerHeadCap AS PlanFeePerHeadCap, pt.ExcludeExpensesFromFee AS PlanExcludeExpenses, pt.MonthlyPrice AS PlanMonthlyPrice,
           pt.IncludedSeats AS PlanIncludedSeats, pt.ExtraSeatPrice AS PlanExtraSeatPrice, pt.MaxSeats AS PlanMaxSeats,
           pt.IncludedAiReports AS PlanIncludedAiReports, pt.AiOveragePrice AS PlanAiOveragePrice, pt.IncludedAiSearches AS PlanIncludedAiSearches,
           -- overrides (NULL = none)
           TRY_CONVERT(DECIMAL(9,6), o1.Value)  AS OverrideFeeRate,
           TRY_CONVERT(DECIMAL(19,2), o2.Value) AS OverridePerInvoiceCap,
           TRY_CONVERT(DECIMAL(19,2), o3.Value) AS OverrideMonthlyMinimum,
           TRY_CONVERT(DECIMAL(19,2), o4.Value) AS OverrideFeePerHeadCap,
           TRY_CONVERT(BIT, o5.Value)           AS OverrideExcludeExpenses,
           TRY_CONVERT(DECIMAL(19,2), o6.Value) AS OverrideMonthlyPrice,
           TRY_CONVERT(INT, o7.Value)           AS OverrideIncludedSeats,
           TRY_CONVERT(DECIMAL(19,2), o8.Value) AS OverrideExtraSeatPrice,
           TRY_CONVERT(INT, o9.Value)           AS OverrideMaxSeats,
           TRY_CONVERT(INT, o10.Value)          AS OverrideIncludedAiReports,
           TRY_CONVERT(INT, o11.Value)          AS OverrideIncludedAiSearches,
           -- effective
           COALESCE(TRY_CONVERT(DECIMAL(9,6), o1.Value), pt.FeeRate)            AS FeeRate,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), o2.Value), pt.PerInvoiceCap)     AS PerInvoiceCap,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), o3.Value), pt.MonthlyMinimum)    AS MonthlyMinimum,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), o4.Value), pt.FeePerHeadCap)     AS FeePerHeadCap,
           COALESCE(TRY_CONVERT(BIT, o5.Value), pt.ExcludeExpensesFromFee)      AS ExcludeExpensesFromFee,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), o6.Value), pt.MonthlyPrice)      AS MonthlyPrice,
           COALESCE(TRY_CONVERT(INT, o7.Value), pt.IncludedSeats)               AS IncludedSeats,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), o8.Value), pt.ExtraSeatPrice)    AS ExtraSeatPrice,
           COALESCE(TRY_CONVERT(INT, o9.Value), pt.MaxSeats)                    AS MaxSeats,
           COALESCE(TRY_CONVERT(INT, o10.Value), pt.IncludedAiReports)          AS IncludedAiReports,
           pt.AiOveragePrice,
           TRY_CONVERT(DECIMAL(19,2), oc.Value)                                 AS PiloOverageCap,
           COALESCE(TRY_CONVERT(INT, o11.Value), pt.IncludedAiSearches)         AS IncludedAiSearches,
           -- contract
           ct.Id AS ContractId, ISNULL(ct.DiscountPct, 0) AS DiscountPct, ct.CommittedSeats, ct.Term AS ContractTerm
    FROM admin.fn_TenantPlanOn(@TenantId, @AsOf) AS tp
    CROSS APPLY admin.fn_PlanTerms(tp.PlanId, @AsOf) AS pt
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Platform.FeeRateOverride', @AsOf) AS o1
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Platform.FeeCapOverride', @AsOf) AS o2
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Platform.MonthlyMinimumOverride', @AsOf) AS o3
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Platform.FeePerHeadCapOverride', @AsOf) AS o4
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Platform.ExcludeExpensesOverride', @AsOf) AS o5
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Plan.MonthlyPriceOverride', @AsOf) AS o6
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Seats.IncludedOverride', @AsOf) AS o7
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Seats.ExtraPriceOverride', @AsOf) AS o8
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Tenant.MaxUsers', @AsOf) AS o9
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Pilo.MonthlyReportsOverride', @AsOf) AS o10
    OUTER APPLY admin.fn_OverrideAsOf(@TenantId, 'Pilo.MonthlySearchesOverride', @AsOf) AS o11
    OUTER APPLY admin.fn_Setting(@TenantId, NULL, 'Pilo.OverageCapAmount') AS oc
    OUTER APPLY (SELECT TOP (1) c.Id, c.DiscountPct, c.CommittedSeats, c.Term FROM admin.TenantContract AS c
                 WHERE c.TenantId = @TenantId AND c.SupersededAt IS NULL AND c.EffectiveFrom <= @AsOf
                 ORDER BY c.EffectiveFrom DESC, c.Id DESC) AS ct;
