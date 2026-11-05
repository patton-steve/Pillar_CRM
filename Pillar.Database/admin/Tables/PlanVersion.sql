-- Every version of a plan's prices and limits (handoff 26), so a price change never surprises a tenant: it takes an EffectiveFrom
-- date and the statement uses the version in force on each day (admin.fn_PlanTerms). Written by admin.usp_Plan_Save; the
-- version in force today is mirrored onto admin.[Plan] by admin.usp_PlanVersion_ApplyDue (AppliedAt). A scheduled version
-- can be cancelled before its date (admin.usp_PlanVersion_Cancel). Pillar-only data: outside RLS, staff procs only.
CREATE TABLE admin.PlanVersion
(
    Id                      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PlanVersion PRIMARY KEY CLUSTERED,
    PlanId                  INT             NOT NULL,
    EffectiveFrom           DATE            NOT NULL,
    FeeRate                 DECIMAL(9,6)    NOT NULL,
    PerInvoiceCap           DECIMAL(19,2)   NULL,
    MonthlyMinimum          DECIMAL(19,2)   NULL,
    FeePerHeadCap           DECIMAL(19,2)   NULL,
    ExcludeExpensesFromFee  BIT             NOT NULL,
    MonthlyPrice            DECIMAL(19,2)   NOT NULL,
    IncludedSeats           INT             NULL,
    ExtraSeatPrice          DECIMAL(19,2)   NULL,
    MaxSeats                INT             NULL,
    IncludedAiReports       INT             NOT NULL,
    AiOveragePrice          DECIMAL(19,2)   NULL,
    IncludedAiSearches      INT             NOT NULL,
    Reason                  NVARCHAR(500)   NULL,
    CreatedAt               DATETIME2(0)    NOT NULL CONSTRAINT DF_PlanVersion_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy               INT             NULL CONSTRAINT DF_PlanVersion_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    AppliedAt               DATETIME2(0)    NULL,      -- copied onto admin.[Plan]
    CancelledAt             DATETIME2(0)    NULL,
    CONSTRAINT CK_PlanVersion_FeeRate CHECK (FeeRate >= 0 AND FeeRate < 1),
    CONSTRAINT CK_PlanVersion_Prices CHECK (MonthlyPrice >= 0 AND (ExtraSeatPrice IS NULL OR ExtraSeatPrice >= 0)
        AND (AiOveragePrice IS NULL OR AiOveragePrice >= 0) AND IncludedAiReports >= 0 AND IncludedAiSearches >= 0
        AND (IncludedSeats IS NULL OR IncludedSeats >= 1) AND (MaxSeats IS NULL OR MaxSeats >= 1)
        AND (FeePerHeadCap IS NULL OR FeePerHeadCap >= 0) AND (PerInvoiceCap IS NULL OR PerInvoiceCap >= 0)
        AND (MonthlyMinimum IS NULL OR MonthlyMinimum >= 0)),
    CONSTRAINT FK_PlanVersion_Plan FOREIGN KEY (PlanId) REFERENCES admin.[Plan] (Id)
);
GO
-- one live version per plan per date
CREATE UNIQUE NONCLUSTERED INDEX UX_PlanVersion_Plan_Date ON admin.PlanVersion (PlanId, EffectiveFrom) WHERE CancelledAt IS NULL;
