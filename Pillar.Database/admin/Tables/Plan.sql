-- Pillar pricing plans. FeeRate is the share of each issued invoice's pre-tax subtotal (0.0250 = 2.5%).
-- Per tenant, the hidden (PLATFORM_ONLY) settings Platform.FeeRateOverride, Platform.FeeCapOverride and
-- Platform.MonthlyMinimumOverride replace FeeRate, PerInvoiceCap and MonthlyMinimum. Set them with admin.usp_Setting_Set.
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
    CONSTRAINT UQ_Plan_Code UNIQUE (Code),
    CONSTRAINT CK_Plan_FeeRate CHECK (FeeRate >= 0 AND FeeRate < 1)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_Plan_IsDefault ON admin.[Plan] (IsDefault) WHERE IsDefault = 1;
