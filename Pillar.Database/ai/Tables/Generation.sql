-- One row per Pilo model call, written by the API after each call (ai.usp_Generation_Log). The source of the tenant's monthly
-- Pilo report count (CountsTowardQuota = 1: an Ask Pilo report; re-running a saved report doesn't call Pilo and isn't logged),
-- the PILO overage line on the platform statement, and Pillar's AI cost per tenant (admin.usp_PlatformPiloCost).
--   Feature  ASK_REPORT, ASK_SEARCH, ASK_HELP, POLISH, RECEIPT (receipt photo read for an expense line; counts toward the
--            allowance only when the PLATFORM_ONLY setting Pilo.ReceiptsCountTowardQuota is on, off by default), OTHER
-- New in handoff 22: the round 5 asks assumed it existed. The API may log more columns later; add them last.
CREATE TABLE ai.Generation
(
    Id                  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Generation PRIMARY KEY CLUSTERED,
    TenantId            INT             NOT NULL,
    AppUserId           INT             NULL,
    Feature             VARCHAR(15)     NOT NULL,
    Model               VARCHAR(100)    NOT NULL,
    InputTokens         INT             NOT NULL CONSTRAINT DF_Generation_InputTokens DEFAULT (0),
    OutputTokens        INT             NOT NULL CONSTRAINT DF_Generation_OutputTokens DEFAULT (0),
    CostUsd             DECIMAL(19,6)   NOT NULL CONSTRAINT DF_Generation_CostUsd DEFAULT (0),
    CountsTowardQuota   BIT             NOT NULL CONSTRAINT DF_Generation_CountsTowardQuota DEFAULT (0),
    Succeeded           BIT             NOT NULL CONSTRAINT DF_Generation_Succeeded DEFAULT (1),
    SavedReportId       INT             NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_Generation_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Generation_Feature CHECK (Feature = 'ASK_REPORT' OR Feature = 'ASK_SEARCH' OR Feature = 'ASK_HELP'
        OR Feature = 'POLISH' OR Feature = 'RECEIPT' OR Feature = 'OTHER'),
    CONSTRAINT UQ_Generation_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_Generation_Tokens CHECK (InputTokens >= 0 AND OutputTokens >= 0 AND CostUsd >= 0),
    CONSTRAINT FK_Generation_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_Generation_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
GO
CREATE NONCLUSTERED INDEX IX_Generation_Tenant_Month ON ai.Generation (TenantId, CreatedAt) INCLUDE (CountsTowardQuota, CostUsd);
