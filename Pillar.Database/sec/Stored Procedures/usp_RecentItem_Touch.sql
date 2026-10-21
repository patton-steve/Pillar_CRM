-- Records that the session user opened a record, and keeps only their 25 most recent.
CREATE PROCEDURE sec.usp_RecentItem_Touch
    @EntityType     VARCHAR(30),
    @EntityPublicId UNIQUEIDENTIFIER,
    @Title          NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @TenantId IS NULL OR @UserId IS NULL THROW 50501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    BEGIN TRAN;

    MERGE sec.UserRecentItem WITH (HOLDLOCK) AS t
    USING (SELECT @TenantId AS TenantId, @UserId AS AppUserId, @EntityType AS EntityType, @EntityPublicId AS EntityPublicId) AS s
    ON t.TenantId = s.TenantId AND t.AppUserId = s.AppUserId AND t.EntityType = s.EntityType AND t.EntityPublicId = s.EntityPublicId
    WHEN MATCHED THEN UPDATE SET Title = @Title, VisitedAt = @Now
    WHEN NOT MATCHED THEN INSERT (TenantId, AppUserId, EntityType, EntityPublicId, Title, VisitedAt)
        VALUES (s.TenantId, s.AppUserId, s.EntityType, s.EntityPublicId, @Title, @Now);

    WITH ranked AS (
        SELECT ROW_NUMBER() OVER (ORDER BY VisitedAt DESC, EntityPublicId) AS rn
        FROM sec.UserRecentItem
        WHERE TenantId = @TenantId AND AppUserId = @UserId
    )
    DELETE FROM ranked WHERE rn > 25;

    COMMIT;
END;
