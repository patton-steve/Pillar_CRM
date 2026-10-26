-- Back office > Tenants: one row per tenant with plan, status, seats, invoices issued and fees this month, last sign-in,
-- and any past-due balance. Filters: @Status, @PlanCode, @Search (name or owner email), @PastDueOnly. Pages with @AfterId.
CREATE PROCEDURE admin.usp_PlatformTenant_List
    @Status         VARCHAR(15) = NULL,
    @PlanCode       VARCHAR(20) = NULL,
    @Search         NVARCHAR(200) = NULL,
    @PastDueOnly    BIT = 0,
    @AfterId        INT = NULL,
    @Top            INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @From DATETIME2(0) = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);

    SELECT TOP (@Top) t.Id, t.PublicId, t.Name, t.Status, p.Code AS PlanCode, p.Name AS PlanName, tt.Name AS TenantType,
           t.CreatedAt, t.SubmittedAt, t.ApprovedAt, t.CancelledAt,
           s.UsedSeats, s.IncludedSeats, s.ExtraSeats,
           (SELECT COUNT(*) FROM ar.Invoice AS i WHERE i.TenantId = t.Id AND i.IssuedAt >= @From) AS InvoicesThisMonth,
           (SELECT ISNULL(SUM(f.FeeAmount), 0) FROM admin.PlatformFee AS f WHERE f.TenantId = t.Id AND f.AccruedAt >= @From) AS FeeThisMonth,
           (SELECT MAX(c.LastLoginAt) FROM sec.UserCredential AS c WHERE c.TenantId = t.Id) AS LastActiveAt,
           (SELECT ISNULL(SUM(ps.BalanceDue), 0) FROM admin.PlatformStatement AS ps WHERE ps.TenantId = t.Id AND ps.Status = 'PAST_DUE') AS PastDueBalance,
           o.Email AS OwnerEmail, o.DisplayName AS OwnerName
    FROM admin.Tenant AS t
    JOIN admin.[Plan] AS p ON p.Id = t.PlanId
    JOIN admin.TenantType AS tt ON tt.Id = t.TenantTypeId
    CROSS APPLY admin.fn_TenantSeats(t.Id) AS s
    OUTER APPLY (SELECT TOP (1) u.Email, u.DisplayName FROM sec.AppUser AS u
                 JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
                 WHERE u.TenantId = t.Id ORDER BY u.Id) AS o
    WHERE (@Status IS NULL OR t.Status = @Status)
      AND (@PlanCode IS NULL OR p.Code = @PlanCode)
      AND (@Search IS NULL OR t.Name LIKE CONCAT(N'%', @Search, N'%') OR o.Email LIKE CONCAT(N'%', @Search, N'%'))
      AND (@PastDueOnly = 0 OR EXISTS (SELECT 1 FROM admin.PlatformStatement AS ps WHERE ps.TenantId = t.Id AND ps.Status = 'PAST_DUE'))
      AND (@AfterId IS NULL OR t.Id > @AfterId)
    ORDER BY t.Id;
END;
