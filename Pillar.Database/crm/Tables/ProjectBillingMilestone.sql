-- Billing schedule for a FIXED project: installments that add up to ClientProject.FixedFeeAmount (Steve 2026-10-20).
-- A milestone is ready to bill when its trigger fires:
--   DATE    BillDate on or before the invoice run's period end
--   MANUAL  someone marks it complete (crm.usp_ProjectMilestone_Complete)
--   TASK    its task is DONE (read live from crm.ClientTask.CompletedAt, so reopening the task un-readies it)
-- Invoice runs bill each ready milestone as one FIXED_FEE line and link it here (InvoiceEntryId); voiding the invoice
-- or deleting the draft releases it. Write the schedule only through crm.usp_ProjectMilestone_Save, which keeps the total
-- equal to the fixed fee and never changes an invoiced milestone.
CREATE TABLE crm.ProjectBillingMilestone
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProjectBillingMilestone PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    ProjectId       INT             NOT NULL,
    Sequence        INT             NOT NULL,
    Name            NVARCHAR(200)   NOT NULL,      -- prints on the invoice line, e.g. "Deposit", "Design sign-off"
    PercentOfFee    DECIMAL(9,6)    NULL,      -- as entered (0.25 = 25%); Amount is what bills
    Amount          DECIMAL(19,2)   NOT NULL,
    TriggerType     VARCHAR(10)     NOT NULL,
    BillDate        DATE            NULL,          -- DATE trigger
    TaskId          INT             NULL,          -- TASK trigger
    CompletedAt     DATETIME2(0)    NULL,          -- MANUAL trigger
    CompletedBy     INT             NULL,
    InvoiceEntryId  INT             NULL,          -- the FIXED_FEE line that bills it (draft or issued)
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_ProjectBillingMilestone_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_ProjectBillingMilestone_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_ProjectBillingMilestone_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_ProjectBillingMilestone_Amount CHECK (Amount > 0),
    CONSTRAINT CK_ProjectBillingMilestone_Percent CHECK (PercentOfFee IS NULL OR (PercentOfFee > 0 AND PercentOfFee <= 1)),
    CONSTRAINT CK_ProjectBillingMilestone_Trigger CHECK (
        (TriggerType = 'DATE'   AND BillDate IS NOT NULL AND TaskId IS NULL)
     OR (TriggerType = 'MANUAL' AND BillDate IS NULL AND TaskId IS NULL)
     OR (TriggerType = 'TASK'   AND TaskId IS NOT NULL AND BillDate IS NULL)),
    CONSTRAINT FK_ProjectBillingMilestone_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id),
    CONSTRAINT FK_ProjectBillingMilestone_Task FOREIGN KEY (TenantId, ProjectId, TaskId) REFERENCES crm.ClientTask (TenantId, ProjectId, Id),
    CONSTRAINT FK_ProjectBillingMilestone_InvoiceEntry FOREIGN KEY (TenantId, InvoiceEntryId) REFERENCES ar.InvoiceEntry (TenantId, Id),
    CONSTRAINT FK_ProjectBillingMilestone_CompletedBy FOREIGN KEY (TenantId, CompletedBy) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_ProjectBillingMilestone_Project ON crm.ProjectBillingMilestone (TenantId, ProjectId, Sequence);
GO
CREATE NONCLUSTERED INDEX IX_ProjectBillingMilestone_Unbilled ON crm.ProjectBillingMilestone (TenantId, ProjectId)
    INCLUDE (TriggerType, BillDate, TaskId, CompletedAt, Amount) WHERE InvoiceEntryId IS NULL;
