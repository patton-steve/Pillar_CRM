-- Back office > tenant detail. Result sets:
--   1 the tenant: status and dates, plan and requested plan, effective fee terms (with which are overrides), seats, Pilo this
--     month, support access (live grant and when it ends), application note and decline reason
--   2 users: name, email, role, status, login, MFA, last sign-in (edit with admin.usp_PlatformUser_Update)
--   3 statements, newest first (last 24)
--   4 timeline, newest first: status changes, plan changes, payments and Pillar's notes
--   5 Pillar's notes
--   6 support tickets
--   7 Pillar-only settings with their effective value and source, for the overrides panel
CREATE PROCEDURE admin.usp_PlatformTenant_Get
    @TenantId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);

    SELECT t.Id, t.PublicId, t.Name, t.Status, t.StatusChangedAt, t.StatusReason, tt.Name AS TenantType, t.TimeZoneId, t.CurrencyCode,
           t.CreatedAt, t.SubmittedAt, t.ApprovedAt, t.ApprovedBy, t.DeclinedReason, t.CancelledAt, t.ApplicationNote,
           p.Code AS PlanCode, p.Name AS PlanName, p.MonthlyPrice, rp.Code AS RequestedPlanCode,
           COALESCE(TRY_CONVERT(DECIMAL(9,6), fr.Value), p.FeeRate) AS FeeRate, CONVERT(BIT, IIF(fr.Source = 'TENANT', 1, 0)) AS FeeRateOverridden,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), fc.Value), p.PerInvoiceCap) AS FeeCap, CONVERT(BIT, IIF(fc.Source = 'TENANT', 1, 0)) AS FeeCapOverridden,
           COALESCE(TRY_CONVERT(DECIMAL(19,2), mm.Value), p.MonthlyMinimum) AS MonthlyMinimum, CONVERT(BIT, IIF(mm.Source = 'TENANT', 1, 0)) AS MonthlyMinimumOverridden,
           s.UsedSeats, s.IncludedSeats, s.ExtraSeats, s.ExtraSeatPrice, s.ExtraSeatsMonthly, s.MaxUsers,
           u.Reports AS PiloReports, u.IncludedReports AS PiloIncluded, u.OverageAmount AS PiloOverage,
           (SELECT ISNULL(SUM(g.CostUsd), 0) FROM ai.Generation AS g WHERE g.TenantId = t.Id AND g.CreatedAt >= CAST(@MonthStart AS DATETIME2(0))) AS AiCostUsd,
           ga.ExpiresAt AS SupportAccessUntil,
           (SELECT COUNT(*) FROM ar.Invoice AS i WHERE i.TenantId = t.Id AND i.IssuedAt >= CAST(@MonthStart AS DATETIME2(0))) AS InvoicesThisMonth,
           (SELECT ISNULL(SUM(f.FeeAmount), 0) FROM admin.PlatformFee AS f WHERE f.TenantId = t.Id AND f.AccruedAt >= CAST(@MonthStart AS DATETIME2(0))) AS FeeThisMonth,
           (SELECT MAX(c.LastLoginAt) FROM sec.UserCredential AS c WHERE c.TenantId = t.Id) AS LastActiveAt,
           (SELECT TOP (1) CONCAT(m.Brand, N' ending ', m.Last4) FROM admin.TenantPaymentMethod AS m
            WHERE m.TenantId = t.Id AND m.IsDefault = 1 AND m.IsActive = 1) AS CardOnFile
    FROM admin.Tenant AS t
    JOIN admin.TenantType AS tt ON tt.Id = t.TenantTypeId
    JOIN admin.[Plan] AS p ON p.Id = t.PlanId
    LEFT JOIN admin.[Plan] AS rp ON rp.Id = t.RequestedPlanId
    CROSS APPLY admin.fn_TenantSeats(t.Id) AS s
    CROSS APPLY admin.fn_PiloUsage(t.Id, @MonthStart) AS u
    OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Platform.FeeRateOverride') AS fr
    OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Platform.FeeCapOverride') AS fc
    OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Platform.MonthlyMinimumOverride') AS mm
    OUTER APPLY (SELECT MAX(g.ExpiresAt) AS ExpiresAt FROM sec.SupportAccessGrant AS g
                 WHERE g.TenantId = t.Id AND g.RevokedAt IS NULL AND g.ExpiresAt > SYSUTCDATETIME()) AS ga
    WHERE t.Id = @TenantId;

    SELECT au.Id, au.DisplayName, au.Email, au.Title, r.Id AS RoleId, r.Name AS RoleName, r.IsOwner, au.Status, au.CanLogin, au.UserType,
           au.IsPlatformAdmin, CONVERT(BIT, IIF(c.MfaEnabledAt IS NOT NULL, 1, 0)) AS MfaEnabled, c.LastLoginAt, c.EmailVerifiedAt, au.CreatedAt
    FROM sec.AppUser AS au
    JOIN sec.Role AS r ON r.TenantId = au.TenantId AND r.Id = au.RoleId
    LEFT JOIN sec.UserCredential AS c ON c.AppUserId = au.Id
    WHERE au.TenantId = @TenantId
    ORDER BY au.Status, au.DisplayName;

    SELECT TOP (24) s.Id, s.StatementNumber, s.PeriodStart, s.Status, s.FeeTotal, s.SubscriptionTotal, s.MinimumAdjustment, s.CreditApplied,
           s.AmountDue, s.AmountPaid, s.BalanceDue, s.FailedAttempts, s.LastAttemptAt, s.NextRetryAt, s.PaidAt
    FROM admin.PlatformStatement AS s
    WHERE s.TenantId = @TenantId
    ORDER BY s.PeriodStart DESC, s.Id DESC;

    SELECT TOP (200) x.OccurredAt, x.Kind, x.Summary, x.Detail
    FROM (
        SELECT a.OccurredAt, a.Action AS Kind, a.Summary, a.Reason AS Detail
        FROM admin.PlatformAudit AS a WHERE a.TenantId = @TenantId
        UNION ALL
        SELECT COALESCE(c.AppliedAt, c.RequestedAt), CONCAT('PLAN_', c.Status),
               CONCAT(fp.Name, N' to ', tp.Name, N' (', LOWER(c.Kind), N', effective ', FORMAT(c.EffectiveDate, 'yyyy-MM-dd'), N')'), c.Note
        FROM admin.TenantPlanChange AS c
        JOIN admin.[Plan] AS fp ON fp.Id = c.FromPlanId
        JOIN admin.[Plan] AS tp ON tp.Id = c.ToPlanId
        WHERE c.TenantId = @TenantId
        UNION ALL
        SELECT pp.AttemptedAt, IIF(pp.Succeeded = 1, 'PAYMENT', 'PAYMENT_FAILED'),
               CONCAT(FORMAT(pp.Amount, 'C', 'en-US'), N' on ', ps.StatementNumber, N' ', ISNULL(pp.MethodDisplay, N'')),
               COALESCE(pp.FailureReason, pp.Note)
        FROM admin.PlatformPayment AS pp
        JOIN admin.PlatformStatement AS ps ON ps.TenantId = pp.TenantId AND ps.Id = pp.StatementId
        WHERE pp.TenantId = @TenantId
        UNION ALL
        SELECT n.CreatedAt, 'NOTE', LEFT(n.Body, 400), NULL
        FROM admin.PlatformTenantNote AS n WHERE n.TenantId = @TenantId AND n.DeletedAt IS NULL
    ) AS x
    ORDER BY x.OccurredAt DESC;

    SELECT n.Id, n.Body, n.CreatedAt, n.CreatedBy, u.DisplayName AS CreatedByName
    FROM admin.PlatformTenantNote AS n
    LEFT JOIN sec.AppUser AS u ON u.Id = n.CreatedBy
    WHERE n.TenantId = @TenantId AND n.DeletedAt IS NULL
    ORDER BY n.Id DESC;

    SELECT k.Id, k.TicketType, k.Subject, k.Status, k.Priority, k.CreatedAt, k.LastMessageAt, k.LastMessageFromPillar
    FROM support.Ticket AS k
    WHERE k.TenantId = @TenantId
    ORDER BY k.Id DESC;

    SELECT d.SettingKey, d.DisplayName, d.Category, d.DataType, d.Visibility, v.Value, v.Source
    FROM admin.SettingDefinition AS d
    CROSS APPLY admin.fn_Setting(@TenantId, NULL, d.SettingKey) AS v
    WHERE d.Visibility <> 'TENANT_EDIT'
    ORDER BY d.Category, d.SortOrder;
END;
