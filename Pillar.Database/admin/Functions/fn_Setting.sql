-- Effective value of one setting: user override -> tenant override -> the tenant's plan (admin.PlanSettingDefault) -> Pillar default.
-- Usage: SELECT Value FROM admin.fn_Setting(@TenantId, @UserId, 'TimeEntry.RequireApproval');
-- Pass @AppUserId = NULL for a tenant-level answer.
CREATE FUNCTION admin.fn_Setting (@TenantId INT, @AppUserId INT, @SettingKey VARCHAR(100))
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) v.Value, v.Source
    FROM admin.SettingDefinition AS d
    CROSS APPLY (
        SELECT u.Value, 'USER' AS Source, 1 AS Precedence
        FROM admin.UserSetting AS u
        WHERE d.AllowUserOverride = 1 AND u.TenantId = @TenantId AND u.AppUserId = @AppUserId AND u.SettingKey = d.SettingKey
        UNION ALL
        SELECT t.Value, 'TENANT', 2
        FROM admin.TenantSetting AS t
        WHERE t.TenantId = @TenantId AND t.SettingKey = d.SettingKey
        UNION ALL
        SELECT p.Value, 'PLAN', 3
        FROM admin.Tenant AS tn
        JOIN admin.PlanSettingDefault AS p ON p.PlanId = tn.PlanId AND p.SettingKey = d.SettingKey
        WHERE tn.Id = @TenantId
        UNION ALL
        SELECT d.DefaultValue, 'DEFAULT', 4
    ) AS v
    WHERE d.SettingKey = @SettingKey
    ORDER BY v.Precedence;
