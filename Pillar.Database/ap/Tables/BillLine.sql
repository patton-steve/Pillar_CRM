-- Lines of a bill or expense report. Quantity x UnitPrice = Amount (mileage: miles x the category's UnitRate).
-- A billable line (needs ProjectId) is picked up by the next invoice run as an EXPENSE line at BillableAmount
-- (Amount plus MarkupPercent) once the bill is approved; InvoiceEntryId links it, like time.
CREATE TABLE ap.BillLine
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BillLine PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    BillId              INT             NOT NULL,
    LineNumber          INT             NOT NULL,
    ExpenseDate         DATE            NULL,
    ExpenseCategoryId   INT             NOT NULL,
    Description         NVARCHAR(500)   NOT NULL,
    Quantity            DECIMAL(19,4)   NOT NULL CONSTRAINT DF_BillLine_Quantity DEFAULT (1),
    UnitPrice           DECIMAL(19,4)   NOT NULL,
    Amount              DECIMAL(19,2)   NOT NULL,
    ProjectId           INT             NULL,
    TaskId              INT             NULL,
    IsBillable          BIT             NOT NULL CONSTRAINT DF_BillLine_IsBillable DEFAULT (0),
    MarkupPercent       DECIMAL(9,4)    NOT NULL CONSTRAINT DF_BillLine_MarkupPercent DEFAULT (0),   -- 0.10 = 10%
    BillableAmount      AS CONVERT(DECIMAL(19,2), ROUND(Amount * (1 + MarkupPercent), 2)) PERSISTED,
    InvoiceEntryId      INT             NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_BillLine_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_BillLine_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_BillLine_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_BillLine_Bill_Line UNIQUE (TenantId, BillId, LineNumber),
    CONSTRAINT CK_BillLine_Billable CHECK (IsBillable = 0 OR ProjectId IS NOT NULL),
    CONSTRAINT CK_BillLine_Markup CHECK (MarkupPercent >= 0),
    CONSTRAINT FK_BillLine_Bill FOREIGN KEY (TenantId, BillId) REFERENCES ap.Bill (TenantId, Id),
    CONSTRAINT FK_BillLine_Category FOREIGN KEY (TenantId, ExpenseCategoryId) REFERENCES lkp.ExpenseCategory (TenantId, Id),
    CONSTRAINT FK_BillLine_Project FOREIGN KEY (TenantId, ProjectId) REFERENCES crm.ClientProject (TenantId, Id),
    -- task must belong to the project
    CONSTRAINT FK_BillLine_Task FOREIGN KEY (TenantId, ProjectId, TaskId) REFERENCES crm.ClientTask (TenantId, ProjectId, Id),
    CONSTRAINT FK_BillLine_InvoiceEntry FOREIGN KEY (TenantId, InvoiceEntryId) REFERENCES ar.InvoiceEntry (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_BillLine_Billable ON ap.BillLine (TenantId, ProjectId)
    INCLUDE (BillableAmount, ExpenseDate) WHERE IsBillable = 1 AND InvoiceEntryId IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_BillLine_InvoiceEntry ON ap.BillLine (TenantId, InvoiceEntryId) WHERE InvoiceEntryId IS NOT NULL;
