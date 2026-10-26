-- Pillar pricing plans. FeeRate is the share of each issued invoice's pre-tax subtotal (0.0250 = 2.5%).
-- Per tenant, the hidden (PLATFORM_ONLY) settings Platform.FeeRateOverride, Platform.FeeCapOverride and
-- Platform.MonthlyMinimumOverride replace FeeRate, PerInvoiceCap and MonthlyMinimum. Set them with admin.usp_Setting_Set.
-- Subscription (handoff 22), billed in arrears on the monthly platform statement:
--   MonthlyPrice       the plan price (Flat $0, AI Powered $39, AI Powered Plus $89, Enterprise $209); prorated by day on a mid-month upgrade
--   IncludedSeats      logins included (people with CanLogin = 1 who aren't disabled); NULL = unlimited
--   ExtraSeatPrice     per extra seat per month, charged on the month's peak seat count
--   IncludedAiReports  Pilo reports a month; AiOveragePrice per report past that (capped by the tenant's Pilo.OverageCapAmount)
-- Per tenant, Seats.IncludedOverride, Seats.ExtraPriceOverride and Pilo.MonthlyReportsOverride replace them (custom quotes).
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
    CONSTRAINT UQ_Plan_Code UNIQUE (Code),
    CONSTRAINT CK_Plan_FeeRate CHECK (FeeRate >= 0 AND FeeRate < 1),
    CONSTRAINT CK_Plan_Prices CHECK (MonthlyPrice >= 0 AND (ExtraSeatPrice IS NULL OR ExtraSeatPrice >= 0)
        AND (AiOveragePrice IS NULL OR AiOveragePrice >= 0) AND IncludedAiReports >= 0 AND (IncludedSeats IS NULL OR IncludedSeats >= 1))
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_Plan_IsDefault ON admin.[Plan] (IsDefault) WHERE IsDefault = 1;
