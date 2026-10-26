-- Pillar approves an application (back office): optionally sets the plan, seat and fee overrides first, then the tenant becomes
-- ACTIVE and team invites open. Also approves a DECLINED tenant Pillar changed its mind about. Logged in Pillar's audit trail
-- and the tenant's audit log. Returns the owners (email, first name) for the API's welcome email.
CREATE PROCEDURE admin.usp_Tenant_Approve
    @TenantId           INT,
    @PlanCode           VARCHAR(20) = NULL,     -- NULL = keep (the default plan, or what Pillar set)
    @IncludedSeats      INT = NULL,             -- custom quote: Seats.IncludedOverride
    @ExtraSeatPrice     DECIMAL(19,2) = NULL,   -- Seats.ExtraPriceOverride
    @FeeRate            DECIMAL(9,6) = NULL,    -- Platform.FeeRateOverride
    @FeeCap             DECIMAL(19,2) = NULL,   -- Platform.FeeCapOverride
    @MonthlyMinimum     DECIMAL(19,2) = NULL,   -- Platform.MonthlyMinimumOverride
    @Note               NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    DECLARE @Status VARCHAR(15), @PlanId INT, @Now DATETIME2(0) = SYSUTCDATETIME(), @Value NVARCHAR(400),
            @Name NVARCHAR(200), @Summary NVARCHAR(400), @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @TenantId);

    SELECT @Status = Status, @Name = Name FROM admin.Tenant WHERE Id = @TenantId;
    IF @Status IS NULL THROW 52202, N'Unknown tenant.', 1;
    IF @Status <> 'PENDING_REVIEW' AND @Status <> 'DECLINED' THROW 52203, N'This tenant isn''t waiting for review.', 1;
    IF @PlanCode IS NOT NULL
    BEGIN
        SELECT @PlanId = Id FROM admin.[Plan] WHERE Code = @PlanCode AND IsActive = 1;
        IF @PlanId IS NULL THROW 52204, N'Unknown plan.', 1;
    END;

    BEGIN TRAN;

    IF @PlanId IS NOT NULL
        EXEC admin.usp_Tenant_ApplyPlan @TenantId = @TenantId, @ToPlanId = @PlanId, @Kind = 'PLATFORM', @Note = N'Set on approval';
    IF @IncludedSeats IS NOT NULL
    BEGIN
        SET @Value = CONVERT(NVARCHAR(400), @IncludedSeats);
        EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Seats.IncludedOverride', @Value = @Value;
    END;
    IF @ExtraSeatPrice IS NOT NULL
    BEGIN
        SET @Value = CONVERT(NVARCHAR(400), @ExtraSeatPrice);
        EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Seats.ExtraPriceOverride', @Value = @Value;
    END;
    IF @FeeRate IS NOT NULL
    BEGIN
        SET @Value = CONVERT(NVARCHAR(400), @FeeRate);
        EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Platform.FeeRateOverride', @Value = @Value;
    END;
    IF @FeeCap IS NOT NULL
    BEGIN
        SET @Value = CONVERT(NVARCHAR(400), @FeeCap);
        EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Platform.FeeCapOverride', @Value = @Value;
    END;
    IF @MonthlyMinimum IS NOT NULL
    BEGIN
        SET @Value = CONVERT(NVARCHAR(400), @MonthlyMinimum);
        EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Platform.MonthlyMinimumOverride', @Value = @Value;
    END;

    UPDATE admin.Tenant
    SET Status = 'ACTIVE', StatusChangedAt = @Now, ApprovedAt = @Now, ApprovedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
        DeclinedReason = NULL, ModifiedAt = @Now
    WHERE Id = @TenantId;

    UPDATE admin.PlatformNotification SET ReadAt = @Now, ReadBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
    WHERE TenantId = @TenantId AND Kind = 'APPLICATION_SUBMITTED' AND ReadAt IS NULL;

    SET @Summary = CONCAT(N'Approved ', @Name, IIF(@PlanCode IS NULL, N'', CONCAT(N' on ', @PlanCode)));
    EXEC admin.usp_PlatformAudit_Write @Action = 'APPROVE', @TenantId = @TenantId, @EntityType = 'TENANT', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Note;
    EXEC admin.usp_Audit_Write @Area = 'billing', @EntityType = 'TENANT', @EntityKey = @Key, @Action = 'ENABLE',
         @Summary = N'Pillar approved the account', @TenantId = @TenantId;

    COMMIT;

    SELECT u.Email, u.FirstName, u.DisplayName
    FROM sec.AppUser AS u
    JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
    WHERE u.TenantId = @TenantId AND u.Status = 'ACTIVE' AND u.CanLogin = 1;
END;
