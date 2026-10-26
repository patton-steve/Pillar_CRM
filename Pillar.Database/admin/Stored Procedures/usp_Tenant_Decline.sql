-- Pillar declines an application (back office). The owner can still sign in and sees the "not approved" screen with the reason.
-- Returns the owners (email, first name) for the API's email.
CREATE PROCEDURE admin.usp_Tenant_Decline
    @TenantId   INT,
    @Reason     NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @Status VARCHAR(15), @Name NVARCHAR(200), @Now DATETIME2(0) = SYSUTCDATETIME(), @Summary NVARCHAR(400),
            @Key NVARCHAR(100) = CONVERT(NVARCHAR(100), @TenantId);
    SELECT @Status = Status, @Name = Name FROM admin.Tenant WHERE Id = @TenantId;
    IF @Status IS NULL THROW 52202, N'Unknown tenant.', 1;
    IF @Status <> 'PENDING_REVIEW' THROW 52203, N'This tenant isn''t waiting for review.', 1;

    BEGIN TRAN;
    UPDATE admin.Tenant SET Status = 'DECLINED', StatusChangedAt = @Now, DeclinedReason = @Reason, ModifiedAt = @Now WHERE Id = @TenantId;
    UPDATE admin.PlatformNotification SET ReadAt = @Now, ReadBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
    WHERE TenantId = @TenantId AND Kind = 'APPLICATION_SUBMITTED' AND ReadAt IS NULL;
    SET @Summary = CONCAT(N'Declined ', @Name);
    EXEC admin.usp_PlatformAudit_Write @Action = 'DECLINE', @TenantId = @TenantId, @EntityType = 'TENANT', @EntityKey = @Key,
         @Summary = @Summary, @Reason = @Reason;
    COMMIT;

    SELECT u.Email, u.FirstName, u.DisplayName
    FROM sec.AppUser AS u
    JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
    WHERE u.TenantId = @TenantId AND u.Status = 'ACTIVE' AND u.CanLogin = 1;
END;
