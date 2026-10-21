-- Every setting with its effective tenant-level value (tenant override, then plan, then Pillar default), for the tenant's Settings screen.
-- PLATFORM_ONLY settings appear only when SESSION_CONTEXT IsPlatformAdmin = 1.
CREATE VIEW admin.vw_TenantSetting
AS
SELECT  t.Id AS TenantId,
        d.SettingKey, d.Category, d.DisplayName, d.Description, d.DataType, d.AllowedValues,
        d.Visibility, d.AllowUserOverride, d.SortOrder,
        COALESCE(ts.Value, ps.Value, d.DefaultValue) AS Value,
        CASE WHEN ts.SettingKey IS NOT NULL THEN 'TENANT' WHEN ps.SettingKey IS NOT NULL THEN 'PLAN' ELSE 'DEFAULT' END AS Source,
        CAST(CASE WHEN d.Visibility = 'TENANT_EDIT' THEN 1 ELSE 0 END AS BIT) AS IsEditable
FROM admin.Tenant AS t
CROSS JOIN admin.SettingDefinition AS d
LEFT JOIN admin.TenantSetting AS ts ON ts.TenantId = t.Id AND ts.SettingKey = d.SettingKey
LEFT JOIN admin.PlanSettingDefault AS ps ON ps.PlanId = t.PlanId AND ps.SettingKey = d.SettingKey
WHERE t.Id = CAST(SESSION_CONTEXT(N'TenantId') AS INT)
  AND (d.Visibility <> 'PLATFORM_ONLY' OR CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT) = 1);
