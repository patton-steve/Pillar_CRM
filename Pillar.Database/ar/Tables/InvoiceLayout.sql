-- A tenant's invoice formats: which report renders the invoice plus the switches the Pillar RDLs read.
-- Seeded per tenant by ar.usp_SeedTenantInvoiceLayouts (SUMMARY = default, TIME_DETAIL).
-- Billing profiles may name one; issue snapshots profile -> tenant default onto ar.Invoice.InvoiceLayoutId.
-- ar.trg_InvoiceLayout_ValidateReport keeps ReportId to an active INVOICE report this tenant may use.
CREATE TABLE ar.InvoiceLayout
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceLayout PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    ReportId        INT             NOT NULL,
    ShowRates       BIT             NOT NULL CONSTRAINT DF_InvoiceLayout_ShowRates DEFAULT (1),       -- Qty / Rate columns
    ShowUserNames   BIT             NOT NULL CONSTRAINT DF_InvoiceLayout_ShowUserNames DEFAULT (1),   -- T: who did the work
    ShowTimeNotes   BIT             NOT NULL CONSTRAINT DF_InvoiceLayout_ShowTimeNotes DEFAULT (1),   -- T: time entry descriptions
    ShowTaxId       BIT             NOT NULL CONSTRAINT DF_InvoiceLayout_ShowTaxId DEFAULT (0),
    Title           NVARCHAR(50)    NOT NULL CONSTRAINT DF_InvoiceLayout_Title DEFAULT (N'INVOICE'),
    HeaderText      NVARCHAR(1000)  NULL,      -- above the lines
    FooterText      NVARCHAR(1000)  NULL,      -- bottom of every page, e.g. late fee terms
    IsDefault       BIT             NOT NULL CONSTRAINT DF_InvoiceLayout_IsDefault DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_InvoiceLayout_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_InvoiceLayout_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_InvoiceLayout_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL,
    CONSTRAINT UQ_InvoiceLayout_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_InvoiceLayout_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_InvoiceLayout_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_InvoiceLayout_Report FOREIGN KEY (ReportId) REFERENCES admin.Report (Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_InvoiceLayout_Tenant_IsDefault ON ar.InvoiceLayout (TenantId) WHERE IsDefault = 1;
