-- "Reset to my role's default": removes the session user's own Today layout, so admin.usp_TodayLayout_Get falls back to
-- their role's published layout, then Pillar's built-in default.
CREATE PROCEDURE admin.usp_TodayLayout_Reset
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    DELETE FROM admin.UserPreference WHERE TenantId = @TenantId AND AppUserId = @UserId AND PrefKey = 'ui.todayLayout';
END;
