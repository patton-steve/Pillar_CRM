-- The owner finishes the setup wizard and sends the application to Pillar (Steve 2026-10-22: "their application for access will be
-- under review and an email is sent to myself with their information"). SETUP -> PENDING_REVIEW, and a back-office inbox item
-- (emailed to the platform admins) carries the company, tenant type, owner and the plan they picked.
-- The owner may keep editing the wizard while PENDING_REVIEW; submitting again updates the plan and note without a second email.
CREATE PROCEDURE admin.usp_Tenant_SubmitApplication
    @RequestedPlanCode  VARCHAR(20) = NULL,
    @Note               NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Status VARCHAR(15), @PlanId INT, @Now DATETIME2(0) = SYSUTCDATETIME(), @Data NVARCHAR(MAX), @Title NVARCHAR(200);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.AppUser AS u JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
                   WHERE u.TenantId = @TenantId AND u.Id = @UserId)
        THROW 52207, N'Only the account owner can send the application.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @UserId AND EmailVerifiedAt IS NOT NULL)
        THROW 52208, N'Please verify your email first.', 1;
    IF @RequestedPlanCode IS NOT NULL
    BEGIN
        SELECT @PlanId = Id FROM admin.[Plan] WHERE Code = @RequestedPlanCode AND IsActive = 1;
        IF @PlanId IS NULL THROW 52204, N'Unknown plan.', 1;
    END;

    BEGIN TRAN;

    SELECT @Status = Status FROM admin.Tenant WITH (UPDLOCK) WHERE Id = @TenantId;
    IF @Status <> 'SETUP' AND @Status <> 'PENDING_REVIEW' THROW 52209, N'This application has already been decided.', 1;

    UPDATE admin.Tenant
    SET Status = 'PENDING_REVIEW', StatusChangedAt = IIF(@Status = 'SETUP', @Now, StatusChangedAt),
        SubmittedAt = IIF(@Status = 'SETUP', @Now, SubmittedAt),
        RequestedPlanId = COALESCE(@PlanId, RequestedPlanId), ApplicationNote = COALESCE(@Note, ApplicationNote),
        ModifiedAt = @Now, ModifiedBy = @UserId
    WHERE Id = @TenantId;

    IF @Status = 'SETUP'
    BEGIN
        SELECT @Title = CONCAT(N'New application: ', t.Name),
               @Data = (SELECT t.Id AS tenantId, t.Name AS company, tt.Name AS tenantType, u.DisplayName AS owner, u.Email AS ownerEmail,
                               u.Phone AS ownerPhone, rp.Name AS requestedPlan, t.ApplicationNote AS note, t.CreatedAt AS signedUpAt
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM admin.Tenant AS t
        JOIN admin.TenantType AS tt ON tt.Id = t.TenantTypeId
        JOIN sec.AppUser AS u ON u.TenantId = t.Id AND u.Id = @UserId
        LEFT JOIN admin.[Plan] AS rp ON rp.Id = t.RequestedPlanId
        WHERE t.Id = @TenantId;

        EXEC admin.usp_PlatformNotification_Raise @Kind = 'APPLICATION_SUBMITTED', @Title = @Title, @TenantId = @TenantId,
             @EntityType = 'TENANT', @EntityId = @TenantId, @DataJson = @Data;
    END;

    COMMIT;
END;
