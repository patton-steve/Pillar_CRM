-- Catalog of SSRS reports Pillar can render. Pillar-delivered reports have OwnerTenantId NULL;
-- a custom report built for one tenant (paid work, Feature.CustomInvoiceLayouts) names that tenant.
-- Global (no RLS); the API lists only OwnerTenantId IS NULL or the caller's tenant.
-- ANALYTIC reports are the Reports page's canned cards (admin.usp_Report_ListCanned): CategoryCode is the card's chip and
-- PermissionCode, when set, hides the card from people without that permission.
CREATE TABLE admin.Report
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Report PRIMARY KEY CLUSTERED,
    Code            VARCHAR(40)     NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    ReportType      VARCHAR(20)     NOT NULL,      -- INVOICE, STATEMENT, ...
    ReportPath      NVARCHAR(400)   NOT NULL,      -- SSRS catalog path, e.g. /Pillar/Invoice_Summary
    Description     NVARCHAR(400)   NULL,
    OwnerTenantId   INT             NULL,
    IsActive        BIT             NOT NULL CONSTRAINT DF_Report_IsActive DEFAULT (1),
    SortOrder       INT             NOT NULL CONSTRAINT DF_Report_SortOrder DEFAULT (0),
    CategoryCode    VARCHAR(20)     NULL,          -- last two columns appended in handoff 20
    PermissionCode  VARCHAR(50)     NULL,
    CONSTRAINT UQ_Report_Code UNIQUE (Code),
    CONSTRAINT CK_Report_ReportType CHECK (ReportType = 'INVOICE' OR ReportType = 'STATEMENT' OR ReportType = 'CREDIT_MEMO'
        OR ReportType = 'ANALYTIC' OR ReportType = 'OTHER'),
    CONSTRAINT FK_Report_Category FOREIGN KEY (CategoryCode) REFERENCES admin.ReportCategory (Code),
    CONSTRAINT FK_Report_Permission FOREIGN KEY (PermissionCode) REFERENCES sec.Permission (Code),
    CONSTRAINT FK_Report_OwnerTenant FOREIGN KEY (OwnerTenantId) REFERENCES admin.Tenant (Id)
);
