-- Every plan change, requested by the tenant (Admin > Billing & plan) or made by Pillar. The tenant's plan history and the
-- source of plan proration on the monthly platform statement.
--   Kind    UPGRADE (to a higher monthly price: applied at once, prorated by day), DOWNGRADE (applied on the 1st of next month),
--           PLATFORM (set by Pillar, e.g. on approval: applied at once)
--   Status  PENDING (a downgrade waiting for EffectiveDate; admin.usp_PlanChange_ApplyDue applies it), APPLIED, CANCELLED
-- Proration is worked out by admin.usp_PlatformStatement_Generate from the APPLIED rows' EffectiveDate, so nothing is stored here.
CREATE TABLE admin.TenantPlanChange
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TenantPlanChange PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    FromPlanId      INT             NOT NULL,
    ToPlanId        INT             NOT NULL,
    Kind            VARCHAR(10)     NOT NULL,
    Status          VARCHAR(10)     NOT NULL,
    EffectiveDate   DATE            NOT NULL,      -- UTC date the new plan starts
    RequestedAt     DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantPlanChange_RequestedAt DEFAULT (SYSUTCDATETIME()),
    RequestedBy     INT             NULL CONSTRAINT DF_TenantPlanChange_RequestedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    AppliedAt       DATETIME2(0)    NULL,
    CancelledAt     DATETIME2(0)    NULL,
    Note            NVARCHAR(500)   NULL,
    CONSTRAINT UQ_TenantPlanChange_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_TenantPlanChange_Kind CHECK (Kind = 'UPGRADE' OR Kind = 'DOWNGRADE' OR Kind = 'PLATFORM'),
    CONSTRAINT CK_TenantPlanChange_Status CHECK (Status = 'PENDING' OR Status = 'APPLIED' OR Status = 'CANCELLED'),
    CONSTRAINT CK_TenantPlanChange_Plans CHECK (FromPlanId <> ToPlanId),
    CONSTRAINT FK_TenantPlanChange_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_TenantPlanChange_FromPlan FOREIGN KEY (FromPlanId) REFERENCES admin.[Plan] (Id),
    CONSTRAINT FK_TenantPlanChange_ToPlan FOREIGN KEY (ToPlanId) REFERENCES admin.[Plan] (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TenantPlanChange_Tenant ON admin.TenantPlanChange (TenantId, Status, EffectiveDate);
GO
-- at most one waiting downgrade per tenant
CREATE UNIQUE NONCLUSTERED INDEX UX_TenantPlanChange_Pending ON admin.TenantPlanChange (TenantId) WHERE Status = 'PENDING';
