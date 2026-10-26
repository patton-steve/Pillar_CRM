-- Saves company notification defaults. Needs settings.notifications. @Defaults is a JSON array:
--   [{"type":"TIMESHEET_DUE","channel":"IN_APP","on":true,"locked":true}, {"type":"INVOICE_PAID","channel":"EMAIL","on":false}]
-- "locked" (default false) forces the channel on for everyone, so it needs "on": true. A row that matches Pillar's default
-- and isn't locked is removed, so later Pillar changes reach the tenant. People's own choices are kept, but a locked
-- channel overrides them. Audited. Errors 51741-51744.
CREATE PROCEDURE admin.usp_TenantNotificationDefault_Set
    @Defaults NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL OR @UserId IS NULL THROW 51741, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'settings.notifications'))
        THROW 51742, N'You need permission to change notification defaults.', 1;
    IF ISJSON(@Defaults) = 0 OR LEFT(LTRIM(@Defaults), 1) <> N'['
        THROW 51743, N'Defaults must be a JSON array of {"type","channel","on","locked"}.', 1;

    CREATE TABLE #d (Code VARCHAR(40) NULL, RawType NVARCHAR(100) NULL, Channel VARCHAR(10) NULL, IsOn BIT NULL, IsLocked BIT NOT NULL,
                     PillarOn BIT NULL);
    INSERT INTO #d (Code, RawType, Channel, IsOn, IsLocked, PillarOn)
    SELECT t.Code, j.[type], UPPER(j.channel), j.[on], ISNULL(j.locked, 0),
           CASE UPPER(j.channel) WHEN 'IN_APP' THEN t.DefaultOn WHEN 'EMAIL' THEN t.DefaultEmailOn END
    FROM OPENJSON(@Defaults) WITH ([type] NVARCHAR(100), channel VARCHAR(10), [on] BIT, locked BIT) AS j
    LEFT JOIN sec.NotificationType AS t ON t.Code = j.[type] COLLATE DATABASE_DEFAULT;

    IF EXISTS (SELECT 1 FROM #d WHERE Code IS NULL OR PillarOn IS NULL OR IsOn IS NULL)
        THROW 51743, N'Each default needs a known type, channel IN_APP or EMAIL, and on true or false.', 1;
    IF EXISTS (SELECT 1 FROM #d WHERE IsLocked = 1 AND IsOn = 0)
        THROW 51744, N'Only a notification that is on can be locked.', 1;
    IF EXISTS (SELECT Code, Channel FROM #d GROUP BY Code, Channel HAVING COUNT(*) > 1)
        THROW 51743, N'Each type and channel can appear once.', 1;

    BEGIN TRAN;
    DELETE t FROM admin.TenantNotificationDefault AS t
    JOIN #d AS d ON d.Code = t.NotificationType AND d.Channel = t.Channel COLLATE DATABASE_DEFAULT
    WHERE t.TenantId = @TenantId AND d.IsOn = d.PillarOn AND d.IsLocked = 0;

    MERGE admin.TenantNotificationDefault AS t
    USING (SELECT Code, Channel, IsOn, IsLocked FROM #d WHERE NOT (IsOn = PillarOn AND IsLocked = 0)) AS s
    ON t.TenantId = @TenantId AND t.NotificationType = s.Code AND t.Channel = s.Channel COLLATE DATABASE_DEFAULT
    WHEN MATCHED THEN UPDATE SET IsOn = s.IsOn, IsLocked = s.IsLocked, ModifiedAt = SYSUTCDATETIME(), ModifiedBy = @UserId
    WHEN NOT MATCHED THEN INSERT (TenantId, NotificationType, Channel, IsOn, IsLocked) VALUES (@TenantId, s.Code, s.Channel, s.IsOn, s.IsLocked);

    EXEC admin.usp_Audit_Write @Area = 'notifications', @EntityType = 'NOTIFICATION_DEFAULT', @Action = 'UPDATE',
         @Summary = N'Changed notification defaults', @ChangeJson = @Defaults;
    COMMIT;
END;
