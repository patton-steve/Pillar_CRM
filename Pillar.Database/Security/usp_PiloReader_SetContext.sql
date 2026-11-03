-- First call on every pillar_ai_reader connection, before any SQL Pilo wrote (handoff 24). Pins the session to one tenant and
-- person with read-only SESSION_CONTEXT keys, so nothing run later on the connection can change them:
--   TenantId          RLS keeps every row to this tenant
--   IsPlatformAdmin 0 the RLS predicate lets IsPlatformAdmin = 1 see every tenant, so it is locked off
--   UserId            the rpt views check this person's permissions (Pilo sees only what they could see in the app)
-- The person must be ACTIVE in that tenant (52411); otherwise UserId stays unset and every view returns no rows.
-- Calling it again with the same tenant and person does nothing (a pooled connection that kept its context); anything else
-- is refused (52410), so the API should drop that connection.
CREATE PROCEDURE sec.usp_PiloReader_SetContext
    @TenantId   INT,
    @UserId     INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurTenant INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @CurUser   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Zero BIT = 0;

    IF @TenantId IS NULL OR @UserId IS NULL THROW 52410, N'TenantId and UserId are required.', 1;
    IF @CurTenant IS NOT NULL OR @CurUser IS NOT NULL
    BEGIN
        IF @CurTenant = @TenantId AND @CurUser = @UserId AND ISNULL(CONVERT(BIT, SESSION_CONTEXT(N'IsPlatformAdmin')), 1) = 0 RETURN;
        THROW 52410, N'This connection is already pinned to another session. Open a new one.', 1;
    END;
    IF SESSION_CONTEXT(N'IsPlatformAdmin') IS NOT NULL THROW 52410, N'This connection is already pinned to another session. Open a new one.', 1;

    EXEC sys.sp_set_session_context N'IsPlatformAdmin', @Zero, @read_only = 1;
    EXEC sys.sp_set_session_context N'TenantId', @TenantId, @read_only = 1;

    IF NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE TenantId = @TenantId AND Id = @UserId AND Status = 'ACTIVE')
        THROW 52411, N'That person is not active in this company.', 1;

    EXEC sys.sp_set_session_context N'UserId', @UserId, @read_only = 1;
END;
