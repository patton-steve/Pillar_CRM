-- New customer sign-up (anonymous, from the public sign-up page): creates the tenant on the default plan, seeds its lookups,
-- settings, invoice layouts and roles, and creates the owner (ACTIVE, Owner role) with the bcrypt hash from the API.
-- Leaves the session's TenantId set to the new tenant. Email verification is the API's job before calling this.
CREATE PROCEDURE admin.usp_Tenant_SignUp
    @TenantName         NVARCHAR(200),
    @OwnerEmail         NVARCHAR(254),
    @OwnerFirstName     NVARCHAR(100),
    @OwnerLastName      NVARCHAR(100) = NULL,
    @PasswordHash       VARCHAR(255),
    @TenantTypeCode     VARCHAR(20) = 'CONTRACTOR',
    @TimeZoneId         NVARCHAR(64) = NULL,
    @TenantId           INT = NULL OUTPUT,
    @AppUserId          INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Normalized NVARCHAR(254) = LOWER(LTRIM(RTRIM(@OwnerEmail)));

    IF CAST(SESSION_CONTEXT(N'TenantId') AS INT) IS NOT NULL
       AND ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 50961, N'Sign up from a fresh session.', 1;
    IF EXISTS (SELECT 1 FROM sec.UserCredential WHERE LoginEmail = @Normalized)
        THROW 50962, N'An account with this email already exists.', 1;

    BEGIN TRAN;

    INSERT INTO admin.Tenant (Name, TenantTypeId, PlanId, TimeZoneId)
    SELECT @TenantName, tt.Id, p.Id, COALESCE(@TimeZoneId, N'Eastern Standard Time')
    FROM admin.TenantType AS tt
    CROSS JOIN admin.[Plan] AS p
    WHERE tt.Code = @TenantTypeCode AND p.IsDefault = 1;
    SET @TenantId = SCOPE_IDENTITY();
    IF @TenantId IS NULL THROW 50963, N'Unknown tenant type, or no default plan.', 1;

    EXEC sec.usp_ReportContext_Set @TenantId = @TenantId;

    EXEC lkp.usp_SyncTenantLookups @TenantId = @TenantId;
    EXEC admin.usp_SeedTenantSettings @TenantId = @TenantId;
    EXEC ar.usp_SeedTenantInvoiceLayouts @TenantId = @TenantId;
    EXEC sec.usp_SeedTenantRoles @TenantId = @TenantId;

    INSERT INTO sec.AppUser (TenantId, Email, FirstName, LastName, RoleId, CanLogin, Status)
    SELECT @TenantId, @OwnerEmail, @OwnerFirstName, @OwnerLastName, r.Id, 1, 'ACTIVE'
    FROM sec.Role AS r
    WHERE r.TenantId = @TenantId AND r.Code = 'OWNER';
    SET @AppUserId = SCOPE_IDENTITY();

    INSERT INTO sec.UserCredential (AppUserId, TenantId, LoginEmail, IsEnabled, PasswordHash, PasswordChangedAt)
    VALUES (@AppUserId, @TenantId, @Normalized, 1, @PasswordHash, SYSUTCDATETIME());

    COMMIT;
END;
