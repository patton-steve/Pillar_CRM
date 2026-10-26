-- Rules on sec.AppUser:
--   only a platform admin session can grant or remove IsPlatformAdmin
--   a new login (insert, or CanLogin/Status turned on) may not exceed Tenant.MaxUsers (people without a login don't count)
--   past the plan's included seats (admin.fn_TenantSeats) a new login is an extra paid seat: only someone with billing.manage may
--   add it (handoff 22). Pillar staff and calls with no user in session (sign-up, seeds) skip this check
--   admin.TenantSeatDaily keeps today's seat count for the monthly SEATS statement line
--   a tenant keeps at least one ACTIVE owner who can log in
--   sec.UserCredential follows the user's email and enabled state; disabling a user revokes its refresh tokens
CREATE TRIGGER sec.trg_AppUser_Rules
ON sec.AppUser
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted AS i LEFT JOIN deleted AS d ON d.Id = i.Id
               WHERE i.IsPlatformAdmin <> ISNULL(d.IsPlatformAdmin, 0))
       AND ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
        THROW 50931, N'Only Pillar can change platform admin access.', 1;

    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT i.TenantId
              FROM inserted AS i LEFT JOIN deleted AS d ON d.Id = i.Id
              WHERE i.CanLogin = 1 AND i.Status <> 'DISABLED'
                AND (d.Id IS NULL OR d.CanLogin = 0 OR d.Status = 'DISABLED')) AS t
        CROSS APPLY admin.fn_Setting(t.TenantId, NULL, 'Tenant.MaxUsers') AS m
        WHERE TRY_CAST(m.Value AS INT) IS NOT NULL
          AND (SELECT COUNT(*) FROM sec.AppUser AS u
               WHERE u.TenantId = t.TenantId AND u.CanLogin = 1 AND u.Status <> 'DISABLED') > TRY_CAST(m.Value AS INT))
        THROW 50932, N'Your plan''s user limit has been reached.', 1;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0
       AND CONVERT(INT, SESSION_CONTEXT(N'UserId')) IS NOT NULL
       AND EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT i.TenantId
              FROM inserted AS i LEFT JOIN deleted AS d ON d.Id = i.Id
              WHERE i.CanLogin = 1 AND i.Status <> 'DISABLED'
                AND (d.Id IS NULL OR d.CanLogin = 0 OR d.Status = 'DISABLED')) AS t
        CROSS APPLY admin.fn_TenantSeats(t.TenantId) AS s
        WHERE s.ExtraSeats > 0
          AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(t.TenantId, CONVERT(INT, SESSION_CONTEXT(N'UserId')), 'billing.manage')))
        THROW 52220, N'All the seats on your plan are in use. Ask an owner or admin to add a seat.', 1;

    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT d.TenantId FROM deleted AS d
              JOIN sec.Role AS r ON r.TenantId = d.TenantId AND r.Id = d.RoleId AND r.IsOwner = 1
              WHERE d.Status = 'ACTIVE' AND d.CanLogin = 1) AS t
        WHERE NOT EXISTS (SELECT 1 FROM sec.AppUser AS u
                          JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId AND r.IsOwner = 1
                          WHERE u.TenantId = t.TenantId AND u.Status = 'ACTIVE' AND u.CanLogin = 1))
        THROW 50933, N'The account needs at least one active owner.', 1;

    UPDATE c
    SET LoginEmail = COALESCE(i.EmailNormalized, c.LoginEmail),
        IsEnabled  = CASE WHEN i.CanLogin = 1 AND i.Status <> 'DISABLED' THEN 1 ELSE 0 END,
        ModifiedAt = SYSUTCDATETIME()
    FROM sec.UserCredential AS c
    JOIN inserted AS i ON i.Id = c.AppUserId;

    MERGE admin.TenantSeatDaily WITH (HOLDLOCK) AS sd
    USING (
        SELECT x.TenantId, CAST(SYSUTCDATETIME() AS DATE) AS SeatDate,
               (SELECT COUNT(*) FROM sec.AppUser AS u WHERE u.TenantId = x.TenantId AND u.CanLogin = 1 AND u.Status <> 'DISABLED') AS Seats
        FROM (SELECT DISTINCT i.TenantId FROM inserted AS i LEFT JOIN deleted AS d ON d.Id = i.Id
              WHERE d.Id IS NULL OR d.CanLogin <> i.CanLogin OR d.Status <> i.Status) AS x
    ) AS s
    ON sd.TenantId = s.TenantId AND sd.SeatDate = s.SeatDate
    WHEN MATCHED THEN UPDATE SET PeakSeats = CASE WHEN s.Seats > sd.PeakSeats THEN s.Seats ELSE sd.PeakSeats END, EndSeats = s.Seats
    WHEN NOT MATCHED THEN INSERT (TenantId, SeatDate, PeakSeats, EndSeats) VALUES (s.TenantId, s.SeatDate, s.Seats, s.Seats);

    UPDATE t
    SET RevokedAt = SYSUTCDATETIME(), RevokedReason = 'DISABLED'
    FROM sec.RefreshToken AS t
    JOIN inserted AS i ON i.Id = t.AppUserId
    WHERE t.RevokedAt IS NULL AND (i.CanLogin = 0 OR i.Status = 'DISABLED');
END;
