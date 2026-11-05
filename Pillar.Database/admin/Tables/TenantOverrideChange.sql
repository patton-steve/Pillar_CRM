-- Every change to a tenant's Pillar-only override settings made through admin.usp_Tenant_SetOverride (handoff 26), with its
-- effective date. A change dated today or earlier is applied at once (AppliedAt, OldValue = the value it replaced); a future one
-- is "scheduled" until admin.usp_PlanVersion_ApplyDue applies it, or admin.usp_TenantOverrideChange_Cancel cancels it.
-- admin.fn_OverrideAsOf reads this history, so a statement for a past month uses the override that was in force then.
-- Value NULL = the override is cleared (back to the plan). Pillar-only data: outside RLS.
CREATE TABLE admin.TenantOverrideChange
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TenantOverrideChange PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    SettingKey      VARCHAR(100)    NOT NULL,
    Value           NVARCHAR(400)   NULL,
    OldValue        NVARCHAR(400)   NULL,
    EffectiveDate   DATE            NOT NULL,
    Reason          NVARCHAR(500)   NOT NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantOverrideChange_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_TenantOverrideChange_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    AppliedAt       DATETIME2(0)    NULL,
    CancelledAt     DATETIME2(0)    NULL,
    CONSTRAINT FK_TenantOverrideChange_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_TenantOverrideChange_Setting FOREIGN KEY (SettingKey) REFERENCES admin.SettingDefinition (SettingKey)
);
GO
CREATE NONCLUSTERED INDEX IX_TenantOverrideChange_Tenant ON admin.TenantOverrideChange (TenantId, SettingKey, EffectiveDate) INCLUDE (Value, OldValue, AppliedAt, CancelledAt);
GO
CREATE NONCLUSTERED INDEX IX_TenantOverrideChange_Due ON admin.TenantOverrideChange (EffectiveDate) WHERE AppliedAt IS NULL AND CancelledAt IS NULL;
