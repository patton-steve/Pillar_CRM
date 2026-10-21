-- Sign-up step: writes the tenant type's starting values as tenant overrides.
-- Settings with no type-specific value simply fall back to SettingDefinition.DefaultValue.
CREATE PROCEDURE admin.usp_SeedTenantSettings
    @TenantId INT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO admin.TenantSetting (TenantId, SettingKey, Value)
    SELECT t.Id, d.SettingKey, d.Value
    FROM admin.Tenant AS t
    JOIN admin.TenantTypeSettingDefault AS d ON d.TenantTypeId = t.TenantTypeId
    WHERE t.Id = @TenantId
      AND NOT EXISTS (SELECT 1 FROM admin.TenantSetting AS x WHERE x.TenantId = t.Id AND x.SettingKey = d.SettingKey);
END;
