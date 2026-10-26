-- Pillar's terms of service and privacy policy, one row per published version. Global (no TenantId). Legal review is pending
-- (Steve 2026-10-22): the terms will say free use and attempts to get around billing have legal consequences.
-- The current version of a Code is the latest with PublishedAt in the past. Sign-up must accept the current TOS
-- (admin.usp_Tenant_SignUp); when a version with RequiresAcceptance = 1 is published, everyone is asked again at their next sign-in
-- (sec.usp_Auth_SecurityPolicy returns MustAcceptTermsId). PRIVACY is shown, not accepted. Publish with admin.usp_LegalDocument_Publish.
CREATE TABLE admin.LegalDocument
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LegalDocument PRIMARY KEY CLUSTERED,
    Code                VARCHAR(10)     NOT NULL,
    Version             NVARCHAR(20)    NOT NULL,      -- e.g. 2026-11
    Title               NVARCHAR(200)   NOT NULL,
    Body                NVARCHAR(MAX)   NULL,          -- sanitized HTML; or Url to a hosted page
    Url                 NVARCHAR(400)   NULL,
    PublishedAt         DATETIME2(0)    NOT NULL,
    RequiresAcceptance  BIT             NOT NULL CONSTRAINT DF_LegalDocument_RequiresAcceptance DEFAULT (1),
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_LegalDocument_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_LegalDocument_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    CONSTRAINT UQ_LegalDocument_Code_Version UNIQUE (Code, Version),
    CONSTRAINT CK_LegalDocument_Code CHECK (Code = 'TOS' OR Code = 'PRIVACY'),
    CONSTRAINT CK_LegalDocument_Content CHECK (Body IS NOT NULL OR Url IS NOT NULL)
);
GO
CREATE NONCLUSTERED INDEX IX_LegalDocument_Current ON admin.LegalDocument (Code, PublishedAt DESC);
