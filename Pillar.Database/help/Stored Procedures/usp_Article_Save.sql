-- Back office > Help articles: adds (@ArticleId NULL) or edits an article. Publishing sets PublishedAt the first time. Pillar only.
CREATE PROCEDURE help.usp_Article_Save
    @Slug           VARCHAR(100),
    @Title          NVARCHAR(200),
    @Body           NVARCHAR(MAX),
    @Category       NVARCHAR(50),
    @Summary        NVARCHAR(400) = NULL,
    @Keywords       NVARCHAR(400) = NULL,
    @SortOrder      INT = 0,
    @IsPublished    BIT = 0,
    @Source         VARCHAR(10) = 'MANUAL',
    @ArticleId      INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF @Slug IS NULL OR @Slug = '' OR @Slug LIKE '%[^a-z0-9-]%' COLLATE Latin1_General_BIN
        THROW 52271, N'The link name uses lower-case letters, digits and hyphens only.', 1;
    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL
        THROW 52271, N'A title and the article text are required.', 1;
    IF EXISTS (SELECT 1 FROM help.Article WHERE Slug = @Slug AND Id <> ISNULL(@ArticleId, 0))
        THROW 52271, N'Another article already uses that link name.', 1;

    IF @ArticleId IS NULL
    BEGIN
        INSERT INTO help.Article (Slug, Title, Summary, Body, Category, Keywords, SortOrder, IsPublished, Source, PublishedAt)
        VALUES (@Slug, @Title, @Summary, @Body, @Category, @Keywords, @SortOrder, @IsPublished, @Source,
                IIF(@IsPublished = 1, SYSUTCDATETIME(), NULL));
        SET @ArticleId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE help.Article
        SET Slug = @Slug, Title = @Title, Summary = @Summary, Body = @Body, Category = @Category, Keywords = @Keywords,
            SortOrder = @SortOrder, IsPublished = @IsPublished, Source = @Source,
            PublishedAt = CASE WHEN @IsPublished = 1 THEN COALESCE(PublishedAt, SYSUTCDATETIME()) ELSE PublishedAt END,
            ModifiedAt = SYSUTCDATETIME(), ModifiedBy = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
        WHERE Id = @ArticleId;
        IF @@ROWCOUNT = 0 THROW 52271, N'Unknown article.', 1;
    END;
END;
