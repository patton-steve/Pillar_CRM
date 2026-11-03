-- Help articles without their text, for the Help page and Pilo Help's search: published ones (Pillar sees drafts too), filtered
-- by @Category and by @Search over title, summary, keywords and text. @Screen (handoff 24) keeps articles tagged with that
-- screen (ScreenTags), for Pilo Help's starting point.
CREATE PROCEDURE help.usp_Article_List
    @Search     NVARCHAR(200) = NULL,
    @Category   NVARCHAR(50) = NULL,
    @Screen     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsPillar BIT = ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0),
            @Like NVARCHAR(210) = CONCAT(N'%', @Search, N'%');

    SELECT a.Id, a.Slug, a.Title, a.Summary, a.Category, a.SortOrder, a.IsPublished, a.Source, a.PublishedAt, a.ModifiedAt, a.ScreenTags
    FROM help.Article AS a
    WHERE (a.IsPublished = 1 OR @IsPillar = 1)
      AND (@Category IS NULL OR a.Category = @Category)
      AND (@Screen IS NULL OR CONCAT(N',', REPLACE(a.ScreenTags, N' ', N''), N',') LIKE CONCAT(N'%,', @Screen, N',%'))
      AND (@Search IS NULL OR a.Title LIKE @Like OR a.Summary LIKE @Like OR a.Keywords LIKE @Like OR a.Body LIKE @Like)
    ORDER BY a.Category, a.SortOrder, a.Title;
END;
