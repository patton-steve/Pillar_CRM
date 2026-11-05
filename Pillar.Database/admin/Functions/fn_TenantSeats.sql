-- A tenant's seats now: UsedSeats (people with CanLogin = 1 who aren't DISABLED; INVITED counts), IncludedSeats (the plan's, or
-- Seats.IncludedOverride; NULL = unlimited), ExtraSeatPrice (the plan's, or Seats.ExtraPriceOverride), ExtraSeats past the
-- included ones, ExtraSeatsMonthly (ExtraSeats x price) and MaxUsers (a hard cap: Tenant.MaxUsers, which only Pillar sets, else
-- the plan's MaxSeats from handoff 26; NULL = none). Handoff 26: CommittedSeats (the contract's seat floor) is appended; when it is
-- above UsedSeats, ExtraSeats and ExtraSeatsMonthly count the committed seats, as the statement does.
CREATE FUNCTION admin.fn_TenantSeats (@TenantId INT)
RETURNS TABLE
AS
RETURN
    SELECT s.UsedSeats, s.IncludedSeats, s.ExtraSeatPrice,
           CASE WHEN s.IncludedSeats IS NOT NULL AND s.Billed > s.IncludedSeats THEN s.Billed - s.IncludedSeats ELSE 0 END AS ExtraSeats,
           CONVERT(DECIMAL(19,2), CASE WHEN s.IncludedSeats IS NOT NULL AND s.Billed > s.IncludedSeats
                                       THEN (s.Billed - s.IncludedSeats) * ISNULL(s.ExtraSeatPrice, 0) ELSE 0 END) AS ExtraSeatsMonthly,
           s.MaxUsers,
           s.CommittedSeats
    FROM (
        SELECT b.UsedSeats, b.IncludedSeats, b.ExtraSeatPrice, b.MaxUsers, b.CommittedSeats,
               CASE WHEN ISNULL(b.CommittedSeats, 0) > b.UsedSeats THEN b.CommittedSeats ELSE b.UsedSeats END AS Billed
        FROM (
            SELECT (SELECT COUNT(*) FROM sec.AppUser AS u
                    WHERE u.TenantId = t.Id AND u.CanLogin = 1 AND u.Status <> 'DISABLED') AS UsedSeats,
                   COALESCE(TRY_CONVERT(INT, io.Value), p.IncludedSeats) AS IncludedSeats,
                   COALESCE(TRY_CONVERT(DECIMAL(19,2), po.Value), p.ExtraSeatPrice) AS ExtraSeatPrice,
                   COALESCE(TRY_CONVERT(INT, mu.Value), p.MaxSeats) AS MaxUsers,
                   (SELECT TOP (1) c.CommittedSeats FROM admin.TenantContract AS c
                    WHERE c.TenantId = t.Id AND c.SupersededAt IS NULL AND c.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
                    ORDER BY c.EffectiveFrom DESC, c.Id DESC) AS CommittedSeats
            FROM admin.Tenant AS t
            JOIN admin.[Plan] AS p ON p.Id = t.PlanId
            OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Seats.IncludedOverride') AS io
            OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Seats.ExtraPriceOverride') AS po
            OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Tenant.MaxUsers') AS mu
            WHERE t.Id = @TenantId
        ) AS b
    ) AS s;
