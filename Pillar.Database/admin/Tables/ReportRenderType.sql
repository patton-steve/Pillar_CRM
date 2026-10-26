-- The Ask Pilo "Show it as" choices, also the icon on a saved report card (admin.SavedReport.RenderType; NULL there means
-- Pilo chose). Pillar-owned, seeded by the post-deploy script; the UI lists the active rows in SortOrder.
CREATE TABLE admin.ReportRenderType
(
    Code            VARCHAR(30)     NOT NULL CONSTRAINT PK_ReportRenderType PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(50)    NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_ReportRenderType_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_ReportRenderType_IsActive DEFAULT (1)
);
