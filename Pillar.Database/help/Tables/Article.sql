-- Help articles for Pilo Help and the Help page, edited in the back office (help.usp_Article_Save). Global (no TenantId).
-- Body is Markdown. Source AI marks articles Pilo drafted (phase 2); a person publishes them. Only IsPublished rows reach tenants.
CREATE TABLE help.Article
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Article PRIMARY KEY CLUSTERED,
    Slug            VARCHAR(100)    NOT NULL,      -- lower-case letters, digits and hyphens, e.g. issue-an-invoice
    Title           NVARCHAR(200)   NOT NULL,
    Summary         NVARCHAR(400)   NULL,
    Body            NVARCHAR(MAX)   NOT NULL,
    Category        NVARCHAR(50)    NOT NULL,      -- e.g. Getting started, Time, Invoicing, Billing & plan
    Keywords        NVARCHAR(400)   NULL,          -- extra search words
    SortOrder       INT             NOT NULL CONSTRAINT DF_Article_SortOrder DEFAULT (0),
    IsPublished     BIT             NOT NULL CONSTRAINT DF_Article_IsPublished DEFAULT (0),
    Source          VARCHAR(10)     NOT NULL CONSTRAINT DF_Article_Source DEFAULT ('MANUAL'),
    PublishedAt     DATETIME2(0)    NULL,
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Article_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Article_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    CONSTRAINT UQ_Article_Slug UNIQUE (Slug),
    CONSTRAINT CK_Article_Source CHECK (Source = 'MANUAL' OR Source = 'AI')
);
GO
CREATE NONCLUSTERED INDEX IX_Article_Category ON help.Article (Category, SortOrder) WHERE IsPublished = 1;
