-- New customer sign-up (anonymous, from the public sign-up page): creates the tenant on the default plan, seeds its lookups,
-- settings, invoice layouts and roles, and creates the owner (ACTIVE, Owner role) with the bcrypt hash from the API.
-- Leaves the session's TenantId set to the new tenant.
-- Handoff 22 (Steve 2026-10-22: sign-up is an application Pillar approves):
--   the tenant starts in SETUP; the owner verifies their email (@VerifyTokenHash stores the VERIFY link the API emails,
--   redeemed by sec.usp_Auth_VerifyEmail), works through the wizard, then admin.usp_Tenant_SubmitApplication sends it for review.
--   @TermsDocumentId must be the current terms of service (admin.LegalDocument) when one is published; the acceptance is
--   recorded with @IpAddress and @UserAgent.
CREATE PROCEDURE admin.usp_Tenant_SignUp
    @TenantName         NVARCHAR(200),
    @OwnerEmail         NVARCHAR(254),
    @OwnerFirstName     NVARCHAR(100),
    @OwnerLastName      NVARCHAR(100) = NULL,
    @PasswordHash       VARCHAR(255),
    @TenantTypeCode     VARCHAR(20) = 'CONTRACTOR',
    @TimeZoneId         NVARCHAR(64) = NULL,
    @TenantId           INT = NULL OUTPUT,
    @AppUserId          INT = NULL OUTPUT,
    @TermsDocumentId    INT = NULL,
    @VerifyTokenHash    BINARY(32) = NULL,
    @VerifyExpiresAt    DATETIME2(0) = NULL,    -- default 24 hours
    @IpAddress          VARCHAR(45) = NULL,
    @UserAgent          NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Normalized NVARCHAR(254) = LOWER(LTRIM(RTRIM(@OwnerEmail))), @Now DATETIME2(0) = SYSUTCDATETIME(), @CurrentTos INT;

    IF CAST(SESSION_CONTEXT(N'TenantId') AS INT) IS NOT NULL
       AND ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 50961, N'Sign up from a fresh session.', 1;
    IF EXISTS (SELECT 1 FROM sec.UserCredential WHERE LoginEmail = @Normalized)
        THROW 50962, N'An account with this email already exists.', 1;

    SELECT TOP (1) @CurrentTos = Id FROM admin.LegalDocument
    WHERE Code = 'TOS' AND PublishedAt <= @Now ORDER BY PublishedAt DESC, Id DESC;
    IF @CurrentTos IS NOT NULL AND (@TermsDocumentId IS NULL OR @TermsDocumentId <> @CurrentTos)
        THROW 52211, N'Please accept the current terms of service.', 1;

    BEGIN TRAN;

    INSERT INTO admin.Tenant (Name, TenantTypeId, PlanId, TimeZoneId, Status, StatusChangedAt)
    SELECT @TenantName, tt.Id, p.Id, COALESCE(@TimeZoneId, N'Eastern Standard Time'), 'SETUP', @Now
    FROM admin.TenantType AS tt
    CROSS JOIN admin.[Plan] AS p
    WHERE tt.Code = @TenantTypeCode AND p.IsDefault = 1;
    SET @TenantId = SCOPE_IDENTITY();
    IF @TenantId IS NULL THROW 50963, N'Unknown tenant type, or no default plan.', 1;

    EXEC sec.usp_ReportContext_Set @TenantId = @TenantId;

    EXEC lkp.usp_SyncTenantLookups @TenantId = @TenantId;
    EXEC admin.usp_SeedTenantSettings @TenantId = @TenantId;
    EXEC ar.usp_SeedTenantInvoiceLayouts @TenantId = @TenantId;
    EXEC admin.usp_SeedTenantEmailTemplates @TenantId = @TenantId;
    EXEC sec.usp_SeedTenantRoles @TenantId = @TenantId;

    INSERT INTO sec.AppUser (TenantId, Email, FirstName, LastName, RoleId, CanLogin, Status)
    SELECT @TenantId, @OwnerEmail, @OwnerFirstName, @OwnerLastName, r.Id, 1, 'ACTIVE'
    FROM sec.Role AS r
    WHERE r.TenantId = @TenantId AND r.Code = 'OWNER';
    SET @AppUserId = SCOPE_IDENTITY();

    INSERT INTO sec.UserCredential (AppUserId, TenantId, LoginEmail, IsEnabled, PasswordHash, PasswordChangedAt)
    VALUES (@AppUserId, @TenantId, @Normalized, 1, @PasswordHash, @Now);

    IF @CurrentTos IS NOT NULL
        INSERT INTO sec.UserLegalAcceptance (TenantId, AppUserId, DocumentId, AcceptedAt, IpAddress, UserAgent)
        VALUES (@TenantId, @AppUserId, @CurrentTos, @Now, @IpAddress, @UserAgent);

    IF @VerifyTokenHash IS NOT NULL
        INSERT INTO sec.UserToken (TenantId, AppUserId, Purpose, TokenHash, ExpiresAt)
        VALUES (@TenantId, @AppUserId, 'VERIFY', @VerifyTokenHash, COALESCE(@VerifyExpiresAt, DATEADD(HOUR, 24, @Now)));

    COMMIT;
END;
