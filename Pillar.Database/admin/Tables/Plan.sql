-- Pillar pricing plans. FeeRate is the share of each issued invoice's pre-tax subtotal (0.0250 = 2.5%).
-- Per tenant, the hidden (PLATFORM_ONLY) settings Platform.FeeRateOverride, Platform.FeeCapOverride and
-- Platform.MonthlyMinimumOverride replace FeeRate, PerInvoiceCap and MonthlyMinimum. Set them with admin.usp_Setting_Set.
-- Subscription (handoff 22), billed in arrears on the monthly platform statement:
--   MonthlyPrice       the plan price (Flat $0, AI Powered $39, AI Powered Plus $89, Enterprise $209); prorated by day on a mid-month upgrade
--   IncludedSeats      logins included (people with CanLogin = 1 who aren't disabled); NULL = unlimited
--   ExtraSeatPrice     per extra seat per month, charged on the month's peak seat count
--   IncludedAiReports  Pilo reports a month; AiOveragePrice per report past that (capped by the tenant's Pilo.OverageCapAmount)
--   IncludedAiSearches Ask Pilo searches a month (handoff 24); a hard limit, no overage. admin.fn_PiloSearchUsage counts them.
-- Per tenant, Seats.IncludedOverride, Seats.ExtraPriceOverride, Pilo.MonthlyReportsOverride and Pilo.MonthlySearchesOverride
-- replace them (custom quotes).
-- Handoff 26: the priced columns are the terms in force today. admin.PlanVersion holds every version with its EffectiveFrom;
-- admin.usp_Plan_Save writes versions and admin.usp_PlanVersion_ApplyDue copies a version here when its date comes.
-- Anything billed for a past or future date reads admin.fn_PlanTerms(@PlanId, @AsOf), never these columns.
CREATE TABLE admin.[Plan]
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Plan PRIMARY KEY CLUSTERED,
    Code            VARCHAR(20)     NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    FeeRate         DECIMAL(9,6)    NOT NULL,
    PerInvoiceCap   DECIMAL(19,2)   NULL,      -- max fee on one invoice; NULL = no cap
    MonthlyMinimum  DECIMAL(19,2)   NULL,      -- applied on the monthly platform statement; NULL = none
    IsDefault       BIT             NOT NULL CONSTRAINT DF_Plan_IsDefault DEFAULT (0),   -- given at sign-up
    IsActive        BIT             NOT NULL CONSTRAINT DF_Plan_IsActive DEFAULT (1),
    MonthlyPrice    DECIMAL(19,2)   NOT NULL CONSTRAINT DF_Plan_MonthlyPrice DEFAULT (0),     -- handoff 22: appended
    IncludedSeats   INT             NULL,
    ExtraSeatPrice  DECIMAL(19,2)   NULL,
    IncludedAiReports INT           NOT NULL CONSTRAINT DF_Plan_IncludedAiReports DEFAULT (0),
    AiOveragePrice  DECIMAL(19,2)   NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_Plan_SortOrder DEFAULT (0),
    IncludedAiSearches INT          NOT NULL CONSTRAINT DF_Plan_IncludedAiSearches DEFAULT (0),   -- handoff 24: appended
    -- handoff 26 (Steve 2026-11-04), appended:
    FeePerHeadCap   DECIMAL(19,2)   NULL,      -- the month's fees are capped at billable heads x this on the statement (CAP line); NULL = no cap
    ExcludeExpensesFromFee BIT      NOT NULL CONSTRAINT DF_Plan_ExcludeExpensesFromFee DEFAULT (1),   -- EXPENSE lines leave the fee base
    IsPublic        BIT             NOT NULL CONSTRAINT DF_Plan_IsPublic DEFAULT (1),   -- 0 = a private plan (custom deal): only Pillar assigns it
    MaxSeats        INT             NULL,      -- hard ceiling on logins; NULL = extra seats allowed and billed
    CONSTRAINT UQ_Plan_Code UNIQUE (Code),
    CONSTRAINT CK_Plan_FeeRate CHECK (FeeRate >= 0 AND FeeRate < 1),
    CONSTRAINT CK_Plan_Prices CHECK (MonthlyPrice >= 0 AND (ExtraSeatPrice IS NULL OR ExtraSeatPrice >= 0)
        AND (AiOveragePrice IS NULL OR AiOveragePrice >= 0) AND IncludedAiReports >= 0 AND (IncludedSeats IS NULL OR IncludedSeats >= 1)),
    CONSTRAINT CK_Plan_AiSearches CHECK (IncludedAiSearches >= 0),
    CONSTRAINT CK_Plan_HeadCap CHECK (FeePerHeadCap IS NULL OR FeePerHeadCap >= 0),
    CONSTRAINT CK_Plan_MaxSeats CHECK (MaxSeats IS NULL OR MaxSeats >= 1)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_Plan_IsDefault ON admin.[Plan] (IsDefault) WHERE IsDefault = 1;
