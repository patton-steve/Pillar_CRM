-- Category chips on the Reports page's canned report cards (admin.Report.CategoryCode). Pillar-owned, seeded by the
-- post-deploy script; the UI renders whatever is active, in SortOrder.
CREATE TABLE admin.ReportCategory
(
    Code            VARCHAR(20)     NOT NULL CONSTRAINT PK_ReportCategory PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(50)    NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_ReportCategory_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_ReportCategory_IsActive DEFAULT (1)
);
