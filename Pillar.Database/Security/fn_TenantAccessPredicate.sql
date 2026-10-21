-- RLS predicate. The API sets these once per connection:
--   EXEC sp_set_session_context N'TenantId', @TenantId, @read_only = 1;
--   EXEC sp_set_session_context N'IsPlatformAdmin', 1, @read_only = 1;   -- platform admin and cross-tenant jobs only
CREATE FUNCTION sec.fn_TenantAccessPredicate (@TenantId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS AccessResult
    WHERE @TenantId = CAST(SESSION_CONTEXT(N'TenantId') AS INT)
       OR CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT) = 1;
