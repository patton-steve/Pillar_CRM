-- Sets the session's TenantId when it has none, so RLS applies; if one is already set it must match.
-- Callers: every report dataset proc (SSRS connects with its own login and no session context; SSRS is reached only through
-- the API, which passes the caller's own TenantId), admin.usp_Tenant_SignUp (the new tenant) and sec.usp_Auth_RedeemToken
-- (the token's tenant).
CREATE PROCEDURE sec.usp_ReportContext_Set
    @TenantId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Current INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT);

    IF @TenantId IS NULL THROW 50901, N'TenantId is required.', 1;
    IF @Current IS NULL
        EXEC sys.sp_set_session_context N'TenantId', @TenantId;
    ELSE IF @Current <> @TenantId AND ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 50902, N'Report tenant does not match the session tenant.', 1;
END;
