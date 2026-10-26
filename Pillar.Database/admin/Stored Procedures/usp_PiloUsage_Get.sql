-- This month's Pilo use for the session tenant (the usage card on Today and Admin > Billing & plan): reports used, included,
-- overage reports and amount so far, the overage cap, and ReportsLeft before overage. The API shows amounts to billing.manage only.
CREATE PROCEDURE admin.usp_PiloUsage_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    IF @TenantId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1) AS PeriodStart, u.Reports, u.IncludedReports,
           CASE WHEN u.IncludedReports > u.Reports THEN u.IncludedReports - u.Reports ELSE 0 END AS ReportsLeft,
           u.OverageReports, u.OveragePrice, u.OverageAmount, u.OverageCap,
           CONVERT(BIT, CASE WHEN u.OverageCap IS NOT NULL AND u.OverageAmount >= u.OverageCap THEN 1 ELSE 0 END) AS CapReached
    FROM admin.fn_PiloUsage(@TenantId, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1)) AS u;
END;
