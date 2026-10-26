-- What moving the tenant to @ToPlanId would run into (admin.usp_PlanChange_Check / _Request):
--   SEATS            WARN   more logins than the plan includes; each extra seat is billed (Detail = extra seats)
--   SAVED_REPORTS    BLOCK  a person has more saved Pilo reports than the plan allows (one row per person)
--   COMPANY_REPORTS  BLOCK  more company Pilo reports than the plan allows
-- A BLOCK must be cleared (reports deleted) before a downgrade can be requested. The limits use the tenant's own override when
-- Pillar set one, else the target plan's value, else Pillar's default.
CREATE FUNCTION admin.fn_PlanChangeIssues (@TenantId INT, @ToPlanId INT)
RETURNS TABLE
AS
RETURN
    WITH lim AS (
        SELECT d.SettingKey, TRY_CONVERT(INT, COALESCE(ts.Value, ps.Value, d.DefaultValue)) AS Allowed
        FROM admin.SettingDefinition AS d
        LEFT JOIN admin.TenantSetting AS ts ON ts.TenantId = @TenantId AND ts.SettingKey = d.SettingKey
        LEFT JOIN admin.PlanSettingDefault AS ps ON ps.PlanId = @ToPlanId AND ps.SettingKey = d.SettingKey
        WHERE d.SettingKey IN ('Pilo.SavedReportsPerUser', 'Pilo.CompanyReports', 'Seats.IncludedOverride')
    ),
    seats AS (
        SELECT (SELECT COUNT(*) FROM sec.AppUser AS u WHERE u.TenantId = @TenantId AND u.CanLogin = 1 AND u.Status <> 'DISABLED') AS Used,
               COALESCE((SELECT Allowed FROM lim WHERE SettingKey = 'Seats.IncludedOverride'), p.IncludedSeats) AS Included,
               p.ExtraSeatPrice, p.Name AS PlanName
        FROM admin.[Plan] AS p WHERE p.Id = @ToPlanId
    )
    SELECT 'SEATS' AS IssueCode, 'WARN' AS Severity, CAST(NULL AS INT) AS AppUserId,
           s.Used AS CurrentCount, s.Included AS AllowedCount,
           CONCAT(s.Used, N' people have a login and ', s.PlanName, N' includes ', s.Included,
                  N'. Each extra seat is ', FORMAT(ISNULL(s.ExtraSeatPrice, 0), 'C', 'en-US'), N' a month.') AS Message
    FROM seats AS s
    WHERE s.Included IS NOT NULL AND s.Used > s.Included
    UNION ALL
    SELECT 'SAVED_REPORTS', 'BLOCK', r.OwnerUserId, COUNT(*), ISNULL(l.Allowed, 0),
           CONCAT(MAX(u.DisplayName), N' has ', COUNT(*), N' saved Pilo reports; the new plan allows ', ISNULL(l.Allowed, 0), N'.')
    FROM admin.SavedReport AS r
    JOIN sec.AppUser AS u ON u.TenantId = r.TenantId AND u.Id = r.OwnerUserId
    CROSS JOIN (SELECT Allowed FROM lim WHERE SettingKey = 'Pilo.SavedReportsPerUser') AS l
    WHERE r.TenantId = @TenantId AND r.IsShared = 0 AND r.DeletedAt IS NULL
    GROUP BY r.OwnerUserId, l.Allowed
    HAVING COUNT(*) > ISNULL(l.Allowed, 0)
    UNION ALL
    SELECT 'COMPANY_REPORTS', 'BLOCK', NULL, COUNT(*), ISNULL(MAX(l.Allowed), 0),
           CONCAT(N'The company has ', COUNT(*), N' shared Pilo reports; the new plan allows ', ISNULL(MAX(l.Allowed), 0), N'.')
    FROM admin.SavedReport AS r
    CROSS JOIN (SELECT Allowed FROM lim WHERE SettingKey = 'Pilo.CompanyReports') AS l
    WHERE r.TenantId = @TenantId AND r.IsShared = 1 AND r.DeletedAt IS NULL
    HAVING COUNT(*) > ISNULL(MAX(l.Allowed), 0);
