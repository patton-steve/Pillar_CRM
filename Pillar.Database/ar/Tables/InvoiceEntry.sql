-- Invoice lines. Run-generated lines:
--   TIME       one line per (project, task, rate); Quantity = hours, Amount = sum of the time entries' AmountBillable
--   RETAINER   one line per retainer project per month (ServicePeriodStart/End); time logged in that month links to it as detail
--   ADJUSTMENT negative line that holds a Not-to-exceed project to its BudgetAmount
-- FIXED_FEE, EXPENSE, DISCOUNT and other ADJUSTMENT lines are added by hand on drafts.
-- Time entries point here through crm.TimeEntry.InvoiceEntryId (the T layout prints them as sub-lines).
CREATE TABLE ar.InvoiceEntry
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceEntry PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    InvoiceId           INT             NOT NULL,
    LineNumber          INT             NOT NULL,
    LineTypeId          INT             NOT NULL,
    ProjectId           INT             NULL,
    TaskId              INT             NULL,
    Description         NVARCHAR(1000)  NOT NULL,
    Quantity            DECIMAL(19,4)   NOT NULL CONSTRAINT DF_InvoiceEntry_Quantity DEFAULT (1),
    UnitPrice           DECIMAL(19,4)   NOT NULL CONSTRAINT DF_InvoiceEntry_UnitPrice DEFAULT (0),
    Amount              DECIMAL(19,2)   NOT NULL,
    IsTaxable           BIT             NOT NULL CONSTRAINT DF_InvoiceEntry_IsTaxable DEFAULT (1),
    ServicePeriodStart  DATE            NULL,
    ServicePeriodEnd    DATE            NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceEntry_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_InvoiceEntry_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_InvoiceEntry_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_InvoiceEntry_Invoice_Line UNIQUE (TenantId, InvoiceId, LineNumber),
    CONSTRAINT FK_InvoiceEntry_Invoice FOREIGN KEY (TenantId, InvoiceId) REFERENCES ar.Invoice (TenantId, Id),
    CONSTRAINT FK_InvoiceEntry_LineType FOREIGN KEY (TenantId, LineTypeId) REFERENCES lkp.InvoiceLineType (TenantId, Id),
    CONSTRAINT FK_InvoiceEntry_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id),
    CONSTRAINT FK_InvoiceEntry_Task FOREIGN KEY (TenantId, TaskId) REFERENCES crm.ClientTask (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_InvoiceEntry_Project ON ar.InvoiceEntry (TenantId, ProjectId) INCLUDE (Amount, ServicePeriodStart) WHERE ProjectId IS NOT NULL;
