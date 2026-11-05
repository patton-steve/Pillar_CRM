-- A tenant's negotiated contract (handoff 26), edited on the back office tenant's Contract & billing tab. Pillar-only data: outside
-- RLS, staff procs only. History is kept: each save adds a row with its EffectiveFrom, and the row in force on a date is the
-- latest live one (SupersededAt NULL) with EffectiveFrom on or before it. Saving again for the same EffectiveFrom supersedes the
-- earlier row (a correction); a future-dated row is "scheduled".
--   Term            MONTHLY or ANNUAL
--   DiscountPct     off the plan price on the statement's PLAN lines, 0 to 1 (0.10 = 10%)
--   CommittedSeats  seats billed at least, so a negotiated seat floor is always charged
--   Prepaid / PrepaidThrough   informational in phase 1 (the statement still bills the plan monthly)
--   The signed contract is a link (DocumentUrl) or an uploaded file (Document*, up to 10 MB).
CREATE TABLE admin.TenantContract
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TenantContract PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    EffectiveFrom       DATE            NOT NULL,
    Term                VARCHAR(10)     NOT NULL CONSTRAINT DF_TenantContract_Term DEFAULT ('MONTHLY'),
    StartDate           DATE            NULL,
    RenewalDate         DATE            NULL,
    Prepaid             BIT             NOT NULL CONSTRAINT DF_TenantContract_Prepaid DEFAULT (0),
    PrepaidThrough      DATE            NULL,
    DiscountPct         DECIMAL(5,4)    NOT NULL CONSTRAINT DF_TenantContract_DiscountPct DEFAULT (0),
    CommittedSeats      INT             NULL,
    Notes               NVARCHAR(2000)  NULL,
    DocumentUrl         NVARCHAR(500)   NULL,
    DocumentName        NVARCHAR(200)   NULL,
    DocumentContentType VARCHAR(100)    NULL,
    DocumentContent     VARBINARY(MAX)  NULL,
    Reason              NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_TenantContract_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_TenantContract_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    SupersededAt        DATETIME2(0)    NULL,
    SupersededBy        INT             NULL,
    CONSTRAINT CK_TenantContract_Term CHECK (Term = 'MONTHLY' OR Term = 'ANNUAL'),
    CONSTRAINT CK_TenantContract_Discount CHECK (DiscountPct >= 0 AND DiscountPct <= 1),
    CONSTRAINT CK_TenantContract_Seats CHECK (CommittedSeats IS NULL OR CommittedSeats >= 0),
    CONSTRAINT CK_TenantContract_Prepaid CHECK (Prepaid = 1 OR PrepaidThrough IS NULL),
    CONSTRAINT CK_TenantContract_Document CHECK (DocumentContent IS NULL OR DATALENGTH(DocumentContent) <= 10485760),
    CONSTRAINT FK_TenantContract_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_TenantContract_Tenant_Date ON admin.TenantContract (TenantId, EffectiveFrom) WHERE SupersededAt IS NULL;
