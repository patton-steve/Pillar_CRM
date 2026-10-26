-- Pillar's catalog of project setup checks (seeded by the post-deploy script; global). Each tenant sets every check to
-- OFF, WARN or BLOCK in admin.TenantProjectSetupCheck; no row = DefaultLevel. BLOCK items keep a project from getting
-- tasks and from leaving PLANNED; WARN items only show on the project's setup card. crm.fn_ProjectSetupIssues
-- evaluates them. AppliesTo is ALL or a comma list of BillingType SystemCodes the check runs for.
CREATE TABLE admin.ProjectSetupCheck
(
    Code            VARCHAR(30)     NOT NULL CONSTRAINT PK_ProjectSetupCheck PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(100)   NOT NULL,
    Description     NVARCHAR(400)   NOT NULL,
    Message         NVARCHAR(200)   NOT NULL,      -- shown on the project's setup card when the check fails
    AppliesTo       VARCHAR(100)    NOT NULL,
    DefaultLevel    VARCHAR(5)      NOT NULL,
    SortOrder       INT             NOT NULL,
    CONSTRAINT CK_ProjectSetupCheck_DefaultLevel CHECK (DefaultLevel = 'OFF' OR DefaultLevel = 'WARN' OR DefaultLevel = 'BLOCK')
);
