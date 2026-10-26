-- Settings > Projects: every setup check with the tenant's level (OFF, WARN or BLOCK) and the default.
CREATE PROCEDURE admin.usp_ProjectSetupCheck_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId'));
    IF @TenantId IS NULL THROW 51402, N'SESSION_CONTEXT TenantId is not set.', 1;

    SELECT c.Code, c.Name, c.Description, c.AppliesTo, c.DefaultLevel, COALESCE(t.Level, c.DefaultLevel) AS Level, c.SortOrder
    FROM admin.ProjectSetupCheck AS c
    LEFT JOIN admin.TenantProjectSetupCheck AS t ON t.TenantId = @TenantId AND t.CheckCode = c.Code
    ORDER BY c.SortOrder;
END;
