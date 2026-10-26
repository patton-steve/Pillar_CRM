-- Back office > Failed charges: every PAST_DUE statement with the tenant, owner contact, balance, attempts, last failure reason
-- and next retry. Retry now is the API charging the card and calling admin.usp_PlatformStatement_RecordPayment; Mark paid is
-- admin.usp_PlatformStatement_MarkPaid; Contact owner uses OwnerEmail.
CREATE PROCEDURE admin.usp_PlatformFailedCharges
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    SELECT s.Id AS StatementId, s.StatementNumber, s.PeriodStart, s.TenantId, t.Name AS TenantName, t.Status AS TenantStatus,
           s.AmountDue, s.AmountPaid, s.BalanceDue, s.FailedAttempts, s.LastAttemptAt, s.NextRetryAt,
           lf.FailureReason AS LastFailureReason, lf.MethodDisplay,
           (SELECT TOP (1) CONCAT(m.Brand, N' ending ', m.Last4) FROM admin.TenantPaymentMethod AS m
            WHERE m.TenantId = s.TenantId AND m.IsDefault = 1 AND m.IsActive = 1) AS CardOnFile,
           o.Email AS OwnerEmail, o.DisplayName AS OwnerName, o.Phone AS OwnerPhone
    FROM admin.PlatformStatement AS s
    JOIN admin.Tenant AS t ON t.Id = s.TenantId
    OUTER APPLY (SELECT TOP (1) p.FailureReason, p.MethodDisplay FROM admin.PlatformPayment AS p
                 WHERE p.TenantId = s.TenantId AND p.StatementId = s.Id AND p.Succeeded = 0 ORDER BY p.Id DESC) AS lf
    OUTER APPLY (SELECT TOP (1) u.Email, u.DisplayName, u.Phone FROM sec.AppUser AS u
                 JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
                 WHERE u.TenantId = s.TenantId AND u.Status = 'ACTIVE' ORDER BY u.Id) AS o
    WHERE s.Status = 'PAST_DUE'
    ORDER BY s.LastAttemptAt;
END;
