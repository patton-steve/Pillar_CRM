-- Saves the signed-in user's notification choices. @Settings is a JSON object of type code -> choice, where a choice is
-- true/false (in-app only, as before) or {"inApp": true, "email": false} (either key optional):
--   {"TASK_CREATED_ON_MY_PROJECT": true, "MENTIONED": {"inApp": true, "email": true}}
-- Types and channels not sent are left as they are. Turning off a channel the tenant locked on is refused (51308).
CREATE PROCEDURE sec.usp_NotificationSetting_Set
    @Settings       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @Locked NVARCHAR(100), @Msg NVARCHAR(400);
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51304, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF ISJSON(@Settings) = 0 OR LEFT(LTRIM(@Settings), 1) <> N'{'
        THROW 51306, N'Notification settings must be a JSON object of type code to true/false or {"inApp","email"}.', 1;

    CREATE TABLE #s (Code VARCHAR(40) NULL, RawKey NVARCHAR(4000) NOT NULL, Ok BIT NOT NULL, InApp BIT NULL, Email BIT NULL);
    INSERT INTO #s (Code, RawKey, Ok, InApp, Email)
    SELECT t.Code, j.[key],
           CASE WHEN j.[type] = 3 THEN 1
                WHEN j.[type] = 5 AND (JSON_VALUE(j.value, '$.inApp') IS NOT NULL OR JSON_VALUE(j.value, '$.email') IS NOT NULL) THEN 1
                ELSE 0 END,
           CASE WHEN j.[type] = 3 THEN IIF(j.value = 'true', 1, 0)
                WHEN j.[type] = 5 THEN CASE JSON_VALUE(j.value, '$.inApp') WHEN 'true' THEN 1 WHEN 'false' THEN 0 END END,
           CASE WHEN j.[type] = 5 THEN CASE JSON_VALUE(j.value, '$.email') WHEN 'true' THEN 1 WHEN 'false' THEN 0 END END
    FROM OPENJSON(@Settings) AS j
    LEFT JOIN sec.NotificationType AS t ON t.Code = j.[key] COLLATE DATABASE_DEFAULT;

    IF EXISTS (SELECT 1 FROM #s WHERE Code IS NULL OR Ok = 0)
        THROW 51307, N'Each notification setting needs a known type code and true/false or {"inApp","email"}.', 1;

    SELECT TOP (1) @Locked = s.Code
    FROM #s AS s
    CROSS APPLY sec.fn_NotificationChannels(@TenantId, @UserId, s.Code) AS c
    WHERE (s.InApp = 0 AND c.InAppLocked = 1) OR (s.Email = 0 AND c.EmailLocked = 1);
    IF @Locked IS NOT NULL
    BEGIN
        SET @Msg = CONCAT(N'Your company keeps ', @Locked, N' switched on.');
        THROW 51308, @Msg, 1;
    END;

    MERGE sec.UserNotificationSetting AS t
    USING #s AS s ON t.TenantId = @TenantId AND t.AppUserId = @UserId AND t.NotificationType = s.Code
    WHEN MATCHED THEN UPDATE SET IsOn = COALESCE(s.InApp, t.IsOn), EmailOn = COALESCE(s.Email, t.EmailOn), ModifiedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (TenantId, AppUserId, NotificationType, IsOn, EmailOn)
        VALUES (@TenantId, @UserId, s.Code,
                COALESCE(s.InApp, (SELECT c.InAppOn FROM sec.fn_NotificationChannels(@TenantId, @UserId, s.Code) AS c)), s.Email);
END;
