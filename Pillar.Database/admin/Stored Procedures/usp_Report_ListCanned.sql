-- Reports page, Canned reports tab: the ANALYTIC reports this person may run (Pillar's, plus any built for this tenant),
-- each with its category chip. A report with a PermissionCode is left out for people without it.
-- Second result set (skip with @IncludeParameters = 0): the USER parameters of those reports, for the viewer panel (label, type, default, pick list).
-- Canned runs never count against Pilo usage.
CREATE PROCEDURE admin.usp_Report_ListCanned
    @IncludeParameters BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51631, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    DECLARE @Visible TABLE (ReportId INT NOT NULL PRIMARY KEY);
    INSERT INTO @Visible (ReportId)
    SELECT r.Id
    FROM admin.Report AS r
    WHERE r.ReportType = 'ANALYTIC' AND r.IsActive = 1
      AND (r.OwnerTenantId IS NULL OR r.OwnerTenantId = @TenantId)
      AND (r.PermissionCode IS NULL OR EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, r.PermissionCode)));

    SELECT r.Id AS ReportId, r.Code, r.Name, r.Description, r.ReportPath, r.CategoryCode, c.Name AS CategoryName,
           c.SortOrder AS CategorySortOrder, r.SortOrder
    FROM @Visible AS v
    JOIN admin.Report AS r ON r.Id = v.ReportId
    LEFT JOIN admin.ReportCategory AS c ON c.Code = r.CategoryCode
    ORDER BY ISNULL(c.SortOrder, 2147483647), r.SortOrder, r.Name;

    IF @IncludeParameters = 1
    SELECT p.ReportId, p.Name, ISNULL(p.Label, p.Name) AS Label, p.DataType, p.DefaultValue, p.ListSource, p.IsRequired, p.SortOrder
    FROM @Visible AS v
    JOIN admin.ReportParameter AS p ON p.ReportId = v.ReportId AND p.Source = 'USER'
    ORDER BY p.ReportId, p.SortOrder;
END;
