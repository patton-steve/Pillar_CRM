-- Pillar suspends, cancels or reinstates a tenant (back office), with a reason. Allowed moves:
--   ACTIVE -> SUSPENDED, SUSPENDED -> ACTIVE, ACTIVE or SUSPENDED -> CANCELLED, CANCELLED -> ACTIVE
-- Suspending or cancelling signs everyone out (refresh tokens revoked; the API refuses sign-in for those statuses) and cancels a
-- waiting downgrade. Cancelling keeps all data (deletion is a support request) and stops plan billing from CancelledAt.
-- Applications are decided with admin.usp_Tenant_Approve / _Decline instead.
CREATE PROCEDURE admin.usp_Tenant_SetStatus
    @TenantId   INT,
    @Status     VARCHAR(15),
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @Old VARCHAR(15), @Name NVARCHAR(200), @Now DATETIME2(0) = SYSUTCDATETIME(), @Summary NVARCHAR(400), @Change NVARCHAR(MAX),
            @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @TenantId), @AuditAction VARCHAR(10);

    BEGIN TRAN;
    SELECT @Old = Status, @Name = Name FROM admin.Tenant WITH (UPDLOCK) WHERE Id = @TenantId;
    IF @Old IS NULL THROW 52202, N'Unknown tenant.', 1;
    IF NOT ((@Old = 'ACTIVE' AND (@Status = 'SUSPENDED' OR @Status = 'CANCELLED'))
         OR (@Old = 'SUSPENDED' AND (@Status = 'ACTIVE' OR @Status = 'CANCELLED'))
         OR (@Old = 'CANCELLED' AND @Status = 'ACTIVE'))
        THROW 52206, N'That status change isn''t allowed.', 1;

    UPDATE admin.Tenant
    SET Status = @Status, StatusChangedAt = @Now, StatusReason = @Reason,
        CancelledAt = CASE WHEN @Status = 'CANCELLED' THEN @Now WHEN @Status = 'ACTIVE' THEN NULL ELSE CancelledAt END,
        ModifiedAt = @Now
    WHERE Id = @TenantId;

    IF @Status <> 'ACTIVE'
    BEGIN
        UPDATE t SET RevokedAt = @Now, RevokedReason = 'ACCOUNT_' + LEFT(@Status, 12)
        FROM sec.RefreshToken AS t
        JOIN sec.UserCredential AS c ON c.AppUserId = t.AppUserId
        WHERE c.TenantId = @TenantId AND t.RevokedAt IS NULL;
        UPDATE admin.TenantPlanChange SET Status = 'CANCELLED', CancelledAt = @Now WHERE TenantId = @TenantId AND Status = 'PENDING';
    END;

    SET @Summary = CONCAT(@Name, N': ', @Old, N' to ', @Status);
    SET @Change = (SELECT N'Status' AS field, @Old AS [from], @Status AS [to] FOR JSON PATH);
    SET @AuditAction = IIF(@Status = 'ACTIVE', 'ENABLE', 'DISABLE');
    EXEC admin.usp_PlatformAudit_Write @Action = 'SET_STATUS', @TenantId = @TenantId, @EntityType = 'TENANT', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    EXEC admin.usp_Audit_Write @Area = 'billing', @EntityType = 'TENANT', @EntityKey = @Key, @Action = @AuditAction,
         @Summary = @Summary, @ChangeJson = @Change, @TenantId = @TenantId;
    COMMIT;
END;
