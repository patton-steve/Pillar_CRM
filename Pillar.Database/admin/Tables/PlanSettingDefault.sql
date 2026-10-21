-- A setting's value for every tenant on a plan, e.g. Feature.Pilo = 1 on the AI plans. Global (no TenantId, no RLS).
-- admin.fn_Setting resolves user -> tenant -> plan -> Pillar default, so changing a tenant's plan changes these at once,
-- and a tenant override (set by a platform admin for PLATFORM_ONLY keys) still wins.
CREATE TABLE admin.PlanSettingDefault
(
    PlanId          INT             NOT NULL,
    SettingKey      VARCHAR(100)    NOT NULL,
    Value           NVARCHAR(400)   NULL,
    CONSTRAINT PK_PlanSettingDefault PRIMARY KEY CLUSTERED (PlanId, SettingKey),
    CONSTRAINT FK_PlanSettingDefault_Plan FOREIGN KEY (PlanId) REFERENCES admin.[Plan] (Id),
    CONSTRAINT FK_PlanSettingDefault_Setting FOREIGN KEY (SettingKey) REFERENCES admin.SettingDefinition (SettingKey)
);
