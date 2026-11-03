-- One saved Pilo report, for running it or opening it in the viewer (handoff 24): your own, or a company report.
-- Result sets: 1 the report (SqlText, ChartSpec, last values in ParameterJson); 2 its parameters, in order;
-- 3 its last @Runs runs (default 10), newest first.
CREATE PROCEDURE admin.usp_SavedReport_Get
    @SavedReportId  INT,
    @Runs           INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51613, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.SavedReport WHERE TenantId = @TenantId AND Id = @SavedReportId AND DeletedAt IS NULL
                   AND (IsShared = 1 OR OwnerUserId = @UserId))
        THROW 51617, N'Saved report not found.', 1;
    IF @Runs IS NULL OR @Runs < 0 OR @Runs > 500 SET @Runs = 10;

    SELECT r.Id AS SavedReportId, r.PublicId, r.Name, r.Prompt, r.SqlText, r.ChartSpec, r.Definition, r.ParameterJson, r.IsShared,
           r.RenderType, r.OwnerUserId, u.DisplayName AS OwnerName, r.CreatedAt, r.ModifiedAt, r.LastRunAt, r.RunCount
    FROM admin.SavedReport AS r
    JOIN sec.AppUser AS u ON u.TenantId = r.TenantId AND u.Id = r.OwnerUserId
    WHERE r.TenantId = @TenantId AND r.Id = @SavedReportId;

    SELECT p.Name, p.Label, p.DataType, p.DefaultValue, p.IsRequired, p.SortOrder
    FROM admin.SavedReportParameter AS p
    WHERE p.TenantId = @TenantId AND p.SavedReportId = @SavedReportId
    ORDER BY p.SortOrder, p.Name;

    SELECT TOP (@Runs) x.Id AS RunId, x.RunAt, x.RunBy, u.DisplayName AS RunByName, x.ParameterJson, x.[RowCount], x.DurationMs,
           x.Succeeded, x.ErrorText
    FROM admin.SavedReportRun AS x
    LEFT JOIN sec.AppUser AS u ON u.TenantId = x.TenantId AND u.Id = x.RunBy
    WHERE x.TenantId = @TenantId AND x.SavedReportId = @SavedReportId
    ORDER BY x.Id DESC;
END;
