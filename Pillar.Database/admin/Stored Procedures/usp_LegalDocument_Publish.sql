-- Pillar publishes a terms of service or privacy policy version (back office). @PublishedAt in the future schedules it.
-- @RequiresAcceptance = 1 on a TOS asks everyone to accept it again at their next sign-in; 0 is for small fixes.
-- Called with no @Code it lists every version instead.
CREATE PROCEDURE admin.usp_LegalDocument_Publish
    @Code               VARCHAR(10) = NULL,
    @Version            NVARCHAR(20) = NULL,
    @Title              NVARCHAR(200) = NULL,
    @Body               NVARCHAR(MAX) = NULL,
    @Url                NVARCHAR(400) = NULL,
    @PublishedAt        DATETIME2(0) = NULL,    -- default now
    @RequiresAcceptance BIT = 1,
    @DocumentId         INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;

    IF @Code IS NULL
    BEGIN
        SELECT d.Id, d.Code, d.Version, d.Title, d.Url, d.PublishedAt, d.RequiresAcceptance, d.CreatedAt,
               (SELECT COUNT(*) FROM sec.UserLegalAcceptance AS a WHERE a.DocumentId = d.Id) AS Acceptances
        FROM admin.LegalDocument AS d
        ORDER BY d.Code, d.PublishedAt DESC;
        RETURN;
    END;

    IF @Version IS NULL OR @Title IS NULL OR (@Body IS NULL AND @Url IS NULL)
        THROW 52213, N'A version, a title, and the text or a link are required.', 1;
    IF EXISTS (SELECT 1 FROM admin.LegalDocument WHERE Code = @Code AND Version = @Version)
        THROW 52213, N'That version already exists.', 1;

    BEGIN TRAN;
    INSERT INTO admin.LegalDocument (Code, Version, Title, Body, Url, PublishedAt, RequiresAcceptance)
    VALUES (@Code, @Version, @Title, @Body, @Url, COALESCE(@PublishedAt, SYSUTCDATETIME()), @RequiresAcceptance);
    SET @DocumentId = SCOPE_IDENTITY();

    DECLARE @Key NVARCHAR(100) = CONCAT(@Code, N' ', @Version), @Summary NVARCHAR(400) = CONCAT(N'Published ', @Title, N' ', @Version);
    EXEC admin.usp_PlatformAudit_Write @Action = 'PUBLISH_LEGAL', @EntityType = 'LEGAL_DOCUMENT', @EntityKey = @Key, @Summary = @Summary;
    COMMIT;
END;
