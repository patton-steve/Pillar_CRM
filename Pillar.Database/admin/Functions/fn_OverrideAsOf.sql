-- A tenant's Pillar-only override for @SettingKey as it stood (or will stand) on @AsOf (handoff 26). Value NULL = no override.
-- From admin.TenantOverrideChange: the latest live change dated on or before @AsOf (scheduled ones count for future dates), else
-- the value the first later applied change replaced, else the tenant's current setting (overrides set before handoff 26).
CREATE FUNCTION admin.fn_OverrideAsOf (@TenantId INT, @SettingKey VARCHAR(100), @AsOf DATE)
RETURNS TABLE
AS
RETURN
    SELECT CASE WHEN a.Id IS NOT NULL THEN a.Value
                WHEN b.Id IS NOT NULL THEN b.OldValue
                ELSE (SELECT s.Value FROM admin.TenantSetting AS s WHERE s.TenantId = @TenantId AND s.SettingKey = @SettingKey) END AS Value,
           CASE WHEN a.Id IS NOT NULL THEN a.EffectiveDate END AS ChangedOn
    FROM (SELECT 1 AS One) AS x
    OUTER APPLY (SELECT TOP (1) c.Id, c.Value, c.EffectiveDate FROM admin.TenantOverrideChange AS c
                 WHERE c.TenantId = @TenantId AND c.SettingKey = @SettingKey AND c.CancelledAt IS NULL AND c.EffectiveDate <= @AsOf
                 ORDER BY c.EffectiveDate DESC, c.Id DESC) AS a
    OUTER APPLY (SELECT TOP (1) c.Id, c.OldValue FROM admin.TenantOverrideChange AS c
                 WHERE c.TenantId = @TenantId AND c.SettingKey = @SettingKey AND c.CancelledAt IS NULL AND c.AppliedAt IS NOT NULL
                   AND c.EffectiveDate > @AsOf
                 ORDER BY c.EffectiveDate, c.Id) AS b;
