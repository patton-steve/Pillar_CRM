-- The project page's setup card: what is still missing, per the tenant's setup checks (see crm.fn_ProjectSetupIssues).
-- @IsReady = 1 when nothing BLOCKs: hide the card, allow tasks and let the status leave PLANNED. WARN rows may remain.
CREATE PROCEDURE crm.usp_Project_SetupStatus
    @ProjectId      INT,
    @IsReady        BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId'));
    IF @TenantId IS NULL THROW 51331, N'SESSION_CONTEXT TenantId is not set.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.ClientProject WHERE TenantId = @TenantId AND Id = @ProjectId AND DeletedAt IS NULL)
        THROW 51332, N'Project not found.', 1;

    SET @IsReady = IIF(EXISTS (SELECT 1 FROM crm.fn_ProjectSetupIssues(@TenantId, @ProjectId) WHERE Severity = 'BLOCK'), 0, 1);
    SELECT Code, Name, Severity, Message FROM crm.fn_ProjectSetupIssues(@TenantId, @ProjectId) ORDER BY SortOrder;
END;
