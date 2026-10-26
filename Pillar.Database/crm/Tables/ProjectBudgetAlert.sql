-- Budget thresholds already announced for a project, so each crossing notifies once. Written by
-- crm.usp_Project_CheckBudgetAlerts; a row is removed when usage drops back under its threshold (e.g. the budget was raised).
-- Basis HOURS compares logged hours with BudgetHours; AMOUNT compares billable amount with BudgetAmount.
CREATE TABLE crm.ProjectBudgetAlert
(
    TenantId            INT             NOT NULL,
    ProjectId           INT             NOT NULL,
    Basis               VARCHAR(10)     NOT NULL,
    ThresholdPercent    INT             NOT NULL,
    UsedPercent         DECIMAL(9,2)    NOT NULL,      -- usage when it was announced
    SentAt              DATETIME2(0)    NOT NULL CONSTRAINT DF_ProjectBudgetAlert_SentAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ProjectBudgetAlert PRIMARY KEY CLUSTERED (TenantId, ProjectId, Basis, ThresholdPercent),
    CONSTRAINT CK_ProjectBudgetAlert_Basis CHECK (Basis = 'HOURS' OR Basis = 'AMOUNT'),
    CONSTRAINT FK_ProjectBudgetAlert_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id)
);
