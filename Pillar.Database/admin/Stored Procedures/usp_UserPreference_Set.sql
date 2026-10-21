-- Saves one of the session user's UI preferences (admin.UserPreference). @Value is JSON text; NULL removes the key.
CREATE PROCEDURE admin.usp_UserPreference_Set
    @PrefKey    VARCHAR(100),
    @Value      NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));

    IF @TenantId IS NULL OR @UserId IS NULL THROW 50501, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    IF @Value IS NULL
        DELETE FROM admin.UserPreference WHERE TenantId = @TenantId AND AppUserId = @UserId AND PrefKey = @PrefKey;
    ELSE
        MERGE admin.UserPreference WITH (HOLDLOCK) AS t
        USING (SELECT @TenantId AS TenantId, @UserId AS AppUserId, @PrefKey AS PrefKey) AS s
        ON t.TenantId = s.TenantId AND t.AppUserId = s.AppUserId AND t.PrefKey = s.PrefKey
        WHEN MATCHED THEN UPDATE SET Value = @Value, ModifiedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (TenantId, AppUserId, PrefKey, Value) VALUES (s.TenantId, s.AppUserId, s.PrefKey, @Value);
END;
