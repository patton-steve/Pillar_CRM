-- One help article by its link name, with the text. Unpublished ones only for Pillar.
CREATE PROCEDURE help.usp_Article_Get
    @Slug VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.Id, a.Slug, a.Title, a.Summary, a.Body, a.Category, a.Keywords, a.IsPublished, a.Source, a.PublishedAt, a.ModifiedAt
    FROM help.Article AS a
    WHERE a.Slug = @Slug AND (a.IsPublished = 1 OR ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 1);
END;
