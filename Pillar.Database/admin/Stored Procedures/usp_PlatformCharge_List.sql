-- One-time charges (Pillar staff, handoff 26), newest first: one tenant's, or every tenant's with @TenantId NULL (e.g. the API's
-- job lists Status PENDING, BillOn CHARGE_NOW to charge them).
CREATE PROCEDURE admin.usp_PlatformCharge_List
    @TenantId   INT = NULL,
    @Status     VARCHAR(10) = NULL,
    @BillOn     VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    SELECT c.Id AS ChargeId, c.TenantId, t.Name AS TenantName, c.Kind, c.Description, c.Amount, c.BillOn, c.ChargeDate, c.Status,
           c.StatementId, s.StatementNumber, c.ProcessorChargeId, c.PaidAt, c.Note, c.Reason, c.CreatedAt, u.DisplayName AS CreatedByName,
           c.CancelledAt
    FROM admin.PlatformCharge AS c
    JOIN admin.Tenant AS t ON t.Id = c.TenantId
    LEFT JOIN admin.PlatformStatement AS s ON s.TenantId = c.TenantId AND s.Id = c.StatementId
    LEFT JOIN sec.AppUser AS u ON u.Id = c.CreatedBy
    WHERE (@TenantId IS NULL OR c.TenantId = @TenantId) AND (@Status IS NULL OR c.Status = @Status) AND (@BillOn IS NULL OR c.BillOn = @BillOn)
    ORDER BY c.CreatedAt DESC, c.Id DESC;
END;
