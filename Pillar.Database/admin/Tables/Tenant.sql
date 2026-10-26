-- A customer account. TenantTypeId seeds starting settings at sign-up (admin.usp_SeedTenantSettings); changing it later does not reseed.
-- Status (handoff 22, Steve 2026-10-22: sign-up is an application Pillar approves):
--   SETUP           signed up; the owner verifies their email and works through the setup wizard
--   PENDING_REVIEW  wizard submitted (admin.usp_Tenant_SubmitApplication); the owner can sign in and edit the wizard, nothing else
--   ACTIVE          approved by Pillar (admin.usp_Tenant_Approve); team invites open
--   DECLINED        not approved (admin.usp_Tenant_Decline); DeclinedReason says why
--   SUSPENDED       switched off by Pillar (admin.usp_Tenant_SetStatus); data kept, nobody can sign in
--   CANCELLED       cancelled through support; data kept until the tenant asks for deletion (no auto-purge)
-- Tenants that existed before handoff 22 are ACTIVE. PlanId changes go through admin.TenantPlanChange.
CREATE TABLE admin.Tenant
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Tenant PRIMARY KEY CLUSTERED,
    PublicId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Tenant_PublicId DEFAULT (NEWSEQUENTIALID()),
    Name            NVARCHAR(200)   NOT NULL,
    TenantTypeId    INT             NOT NULL,
    PlanId          INT             NOT NULL,
    TimeZoneId      NVARCHAR(64)    NOT NULL CONSTRAINT DF_Tenant_TimeZoneId DEFAULT (N'Eastern Standard Time'),
    CurrencyCode    CHAR(3)         NOT NULL CONSTRAINT DF_Tenant_CurrencyCode DEFAULT ('USD'),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Tenant_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Tenant_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    Status          VARCHAR(15)     NOT NULL CONSTRAINT DF_Tenant_Status DEFAULT ('ACTIVE'),   -- handoff 22: appended
    StatusChangedAt DATETIME2(0)    NULL,
    StatusReason    NVARCHAR(500)   NULL,      -- why it was suspended, cancelled or reinstated
    SubmittedAt     DATETIME2(0)    NULL,      -- application sent for review
    ApprovedAt      DATETIME2(0)    NULL,      -- plan billing starts here (NULL on older tenants = CreatedAt)
    ApprovedBy      INT             NULL,      -- the Pillar admin's AppUser.Id (in Pillar's own tenant, so no FK)
    DeclinedReason  NVARCHAR(500)   NULL,
    CancelledAt     DATETIME2(0)    NULL,      -- plan billing stops here
    RequestedPlanId INT             NULL,      -- plan picked in the wizard; Pillar sets the real one on approval
    ApplicationNote NVARCHAR(1000)  NULL,      -- anything the applicant wants Pillar to know
    CONSTRAINT UQ_Tenant_PublicId UNIQUE (PublicId),
    CONSTRAINT FK_Tenant_TenantType FOREIGN KEY (TenantTypeId) REFERENCES admin.TenantType (Id),
    CONSTRAINT FK_Tenant_Plan FOREIGN KEY (PlanId) REFERENCES admin.[Plan] (Id),
    CONSTRAINT FK_Tenant_RequestedPlan FOREIGN KEY (RequestedPlanId) REFERENCES admin.[Plan] (Id),
    CONSTRAINT CK_Tenant_Status CHECK (Status = 'SETUP' OR Status = 'PENDING_REVIEW' OR Status = 'ACTIVE' OR Status = 'DECLINED'
        OR Status = 'SUSPENDED' OR Status = 'CANCELLED')
);
GO
CREATE NONCLUSTERED INDEX IX_Tenant_Status ON admin.Tenant (Status) INCLUDE (PlanId, SubmittedAt);
