-- The back office tenant's Contract & billing tab (Pillar staff, handoff 26). Five result sets:
--   1. effective terms grid: one row per priced term with the plan's value, the override (OverrideKey is the setting to pass to
--      admin.usp_Tenant_SetOverride; NULL = not overridable there), the effective value and its Source (PLAN, OVERRIDE or
--      CONTRACT), plus the next scheduled override change. Values are numbers (ExcludeExpensesFromFee 0 or 1; rates as decimals).
--   2. contracts: every row, newest first, Status CURRENT / SCHEDULED / PAST / SUPERSEDED (the file itself via _GetDocument)
--   3. seats now: used, included, committed, billed, extra, max and this month's extra seat charge so far
--   4. scheduled changes: plan versions for the tenant's plan, override changes, a waiting plan change and future contracts
--   5. override history (newest 50)
CREATE PROCEDURE admin.usp_TenantTerms_Get
    @TenantId   INT,
    @AsOf       DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;
    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET @AsOf = ISNULL(@AsOf, @Today);

    SELECT r.SortOrder, r.TermKey, r.Label, r.Unit, r.PlanValue, r.OverrideKey, r.OverrideValue, r.EffectiveValue,
           CASE WHEN r.TermKey IN ('DiscountPct', 'CommittedSeats') THEN 'CONTRACT'
                WHEN r.OverrideValue IS NOT NULL THEN 'OVERRIDE' ELSE 'PLAN' END AS Source,
           sc.Id AS ScheduledChangeId, sc.EffectiveDate AS ScheduledDate, TRY_CONVERT(DECIMAL(19,6), sc.Value) AS ScheduledValue,
           CONVERT(BIT, IIF(sc.Id IS NOT NULL AND sc.Value IS NULL, 1, 0)) AS ScheduledClear
    FROM admin.fn_TenantTerms(@TenantId, @AsOf) AS t
    CROSS APPLY (VALUES
        (10,  'FeeRate',                N'Platform fee rate',            'RATE',   CONVERT(DECIMAL(19,6), t.PlanFeeRate),            'Platform.FeeRateOverride',         CONVERT(DECIMAL(19,6), t.OverrideFeeRate),            CONVERT(DECIMAL(19,6), t.FeeRate)),
        (20,  'FeePerHeadCap',          N'Fee cap per billable person',  'MONEY',  t.PlanFeePerHeadCap,                              'Platform.FeePerHeadCapOverride',   t.OverrideFeePerHeadCap,                              t.FeePerHeadCap),
        (30,  'PerInvoiceCap',          N'Fee cap per invoice',          'MONEY',  t.PlanPerInvoiceCap,                              'Platform.FeeCapOverride',          t.OverridePerInvoiceCap,                              t.PerInvoiceCap),
        (40,  'MonthlyMinimum',         N'Monthly minimum fee',          'MONEY',  t.PlanMonthlyMinimum,                             'Platform.MonthlyMinimumOverride',  t.OverrideMonthlyMinimum,                             t.MonthlyMinimum),
        (50,  'ExcludeExpensesFromFee', N'Rebilled expenses left out of the fee', 'BIT', CONVERT(DECIMAL(19,6), t.PlanExcludeExpenses), 'Platform.ExcludeExpensesOverride', CONVERT(DECIMAL(19,6), t.OverrideExcludeExpenses), CONVERT(DECIMAL(19,6), t.ExcludeExpensesFromFee)),
        (60,  'MonthlyPrice',           N'Monthly plan price',           'MONEY',  t.PlanMonthlyPrice,                               'Plan.MonthlyPriceOverride',        t.OverrideMonthlyPrice,                               t.MonthlyPrice),
        (70,  'IncludedSeats',          N'Included seats',               'COUNT',  t.PlanIncludedSeats,                              'Seats.IncludedOverride',           t.OverrideIncludedSeats,                              t.IncludedSeats),
        (80,  'ExtraSeatPrice',         N'Extra seat price',             'MONEY',  t.PlanExtraSeatPrice,                             'Seats.ExtraPriceOverride',         t.OverrideExtraSeatPrice,                             t.ExtraSeatPrice),
        (90,  'MaxSeats',               N'Max seats',                    'COUNT',  t.PlanMaxSeats,                                   'Tenant.MaxUsers',                  t.OverrideMaxSeats,                                   t.MaxSeats),
        (100, 'IncludedAiReports',      N'Pilo reports a month',         'COUNT',  t.PlanIncludedAiReports,                          'Pilo.MonthlyReportsOverride',      t.OverrideIncludedAiReports,                          t.IncludedAiReports),
        (110, 'AiOveragePrice',         N'Pilo overage price per report','MONEY',  t.PlanAiOveragePrice,                             NULL,                               NULL,                                                 t.AiOveragePrice),
        (120, 'IncludedAiSearches',     N'Ask Pilo searches a month',    'COUNT',  t.PlanIncludedAiSearches,                         'Pilo.MonthlySearchesOverride',     t.OverrideIncludedAiSearches,                         t.IncludedAiSearches),
        (130, 'DiscountPct',            N'Contract discount on the plan price', 'RATE', NULL,                                        NULL,                               NULL,                                                 t.DiscountPct),
        (140, 'CommittedSeats',         N'Committed seats',              'COUNT',  NULL,                                             NULL,                               NULL,                                                 t.CommittedSeats)
    ) AS r (SortOrder, TermKey, Label, Unit, PlanValue, OverrideKey, OverrideValue, EffectiveValue)
    OUTER APPLY (SELECT TOP (1) c.Id, c.EffectiveDate, c.Value FROM admin.TenantOverrideChange AS c
                 WHERE c.TenantId = @TenantId AND c.SettingKey = r.OverrideKey AND c.AppliedAt IS NULL AND c.CancelledAt IS NULL
                   AND c.EffectiveDate > @AsOf
                 ORDER BY c.EffectiveDate, c.Id) AS sc
    ORDER BY r.SortOrder;

    SELECT c.Id AS ContractId, c.EffectiveFrom,
           CASE WHEN c.SupersededAt IS NOT NULL THEN 'SUPERSEDED' WHEN c.EffectiveFrom > @AsOf THEN 'SCHEDULED'
                WHEN c.Id = (SELECT TOP (1) x.Id FROM admin.TenantContract AS x
                             WHERE x.TenantId = c.TenantId AND x.SupersededAt IS NULL AND x.EffectiveFrom <= @AsOf
                             ORDER BY x.EffectiveFrom DESC, x.Id DESC) THEN 'CURRENT'
                ELSE 'PAST' END AS Status,
           c.Term, c.StartDate, c.RenewalDate, c.Prepaid, c.PrepaidThrough, c.DiscountPct, c.CommittedSeats, c.Notes,
           c.DocumentUrl, c.DocumentName, c.DocumentContentType, CONVERT(BIT, IIF(c.DocumentContent IS NULL, 0, 1)) AS HasDocumentFile,
           c.Reason, c.CreatedAt, u.DisplayName AS CreatedByName, c.SupersededAt
    FROM admin.TenantContract AS c
    LEFT JOIN sec.AppUser AS u ON u.Id = c.CreatedBy
    WHERE c.TenantId = @TenantId
    ORDER BY c.EffectiveFrom DESC, c.Id DESC;

    SELECT s.UsedSeats, s.IncludedSeats, s.CommittedSeats,
           CASE WHEN ISNULL(s.CommittedSeats, 0) > s.UsedSeats THEN s.CommittedSeats ELSE s.UsedSeats END AS BilledSeats,
           s.ExtraSeats, s.MaxUsers AS MaxSeats, s.ExtraSeatPrice, s.ExtraSeatsMonthly AS NextSeatCharge
    FROM admin.fn_TenantSeats(@TenantId) AS s;

    SELECT x.Kind, x.ChangeId, x.EffectiveDate, x.Description, x.Reason
    FROM (
        SELECT 'PLAN_VERSION' AS Kind, v.Id AS ChangeId, v.EffectiveFrom AS EffectiveDate,
               CONCAT(p.Name, N' plan terms change (fee ', FORMAT(v.FeeRate * 100, '0.##'), N'%',
                      IIF(v.FeePerHeadCap IS NULL, N'', CONCAT(N', cap ', FORMAT(v.FeePerHeadCap, 'C', 'en-US'), N' a person')),
                      N', price ', FORMAT(v.MonthlyPrice, 'C', 'en-US'), N')') AS Description, v.Reason
        FROM admin.Tenant AS t
        JOIN admin.[Plan] AS p ON p.Id = t.PlanId
        JOIN admin.PlanVersion AS v ON v.PlanId = t.PlanId AND v.CancelledAt IS NULL AND v.EffectiveFrom > @AsOf
        WHERE t.Id = @TenantId
        UNION ALL
        SELECT 'OVERRIDE', c.Id, c.EffectiveDate,
               CONCAT(c.SettingKey, IIF(c.Value IS NULL, N' cleared', CONCAT(N' set to ', c.Value))), c.Reason
        FROM admin.TenantOverrideChange AS c
        WHERE c.TenantId = @TenantId AND c.AppliedAt IS NULL AND c.CancelledAt IS NULL
        UNION ALL
        SELECT 'PLAN_CHANGE', c.Id, c.EffectiveDate, CONCAT(N'Move to the ', p.Name, N' plan'), c.Note
        FROM admin.TenantPlanChange AS c
        JOIN admin.[Plan] AS p ON p.Id = c.ToPlanId
        WHERE c.TenantId = @TenantId AND c.Status = 'PENDING'
        UNION ALL
        SELECT 'CONTRACT', c.Id, c.EffectiveFrom, CONCAT(N'Contract terms (', c.Term, N')'), c.Reason
        FROM admin.TenantContract AS c
        WHERE c.TenantId = @TenantId AND c.SupersededAt IS NULL AND c.EffectiveFrom > @AsOf
    ) AS x
    ORDER BY x.EffectiveDate, x.Kind;

    SELECT TOP (50) c.Id AS OverrideChangeId, c.SettingKey, c.OldValue, c.Value, c.EffectiveDate,
           CASE WHEN c.CancelledAt IS NOT NULL THEN 'CANCELLED' WHEN c.AppliedAt IS NULL THEN 'SCHEDULED' ELSE 'APPLIED' END AS Status,
           c.Reason, c.CreatedAt, u.DisplayName AS CreatedByName, c.AppliedAt, c.CancelledAt
    FROM admin.TenantOverrideChange AS c
    LEFT JOIN sec.AppUser AS u ON u.Id = c.CreatedBy
    WHERE c.TenantId = @TenantId
    ORDER BY c.CreatedAt DESC, c.Id DESC;
END;
