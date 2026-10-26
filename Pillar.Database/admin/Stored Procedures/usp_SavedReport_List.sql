-- Reports page tabs: @Scope MINE = my saved AI reports, COMPANY = company AI reports. Also returns the plan limits
-- and current counts (second result set) so the UI can show "3 of 5" and offer replace at the limit.
CREATE PROCEDURE admin.usp_SavedReport_List
    @Scope VARCHAR(10) = 'MINE'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51613, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT r.Id AS SavedReportId, r.PublicId, r.Name, r.Prompt, r.Definition, r.ParameterJson, r.IsShared, r.RenderType, rt.Name AS RenderTypeName,
           r.OwnerUserId, u.DisplayName AS OwnerName, r.CreatedAt, r.ModifiedAt, r.LastRunAt, r.RunCount
    FROM admin.SavedReport AS r
    JOIN sec.AppUser AS u ON u.TenantId = r.TenantId AND u.Id = r.OwnerUserId
    LEFT JOIN admin.ReportRenderType AS rt ON rt.Code = r.RenderType
    WHERE r.TenantId = @TenantId AND r.DeletedAt IS NULL
      AND ((@Scope = 'MINE' AND r.IsShared = 0 AND r.OwnerUserId = @UserId) OR (@Scope = 'COMPANY' AND r.IsShared = 1))
    ORDER BY r.Name;

    SELECT ISNULL((SELECT TRY_CONVERT(INT, Value) FROM admin.fn_Setting(@TenantId, NULL, 'Pilo.SavedReportsPerUser')), 0) AS MyLimit,
           (SELECT COUNT(*) FROM admin.SavedReport
            WHERE TenantId = @TenantId AND OwnerUserId = @UserId AND IsShared = 0 AND DeletedAt IS NULL) AS MyCount,
           ISNULL((SELECT TRY_CONVERT(INT, Value) FROM admin.fn_Setting(@TenantId, NULL, 'Pilo.CompanyReports')), 0) AS CompanyLimit,
           (SELECT COUNT(*) FROM admin.SavedReport WHERE TenantId = @TenantId AND IsShared = 1 AND DeletedAt IS NULL) AS CompanyCount;
END;
