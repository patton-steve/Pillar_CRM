-- A tenant's seats now: UsedSeats (people with CanLogin = 1 who aren't DISABLED; INVITED counts), IncludedSeats (the plan's, or
-- Seats.IncludedOverride; NULL = unlimited), ExtraSeatPrice (the plan's, or Seats.ExtraPriceOverride), ExtraSeats past the
-- included ones, ExtraSeatsMonthly (ExtraSeats x price) and MaxUsers (Tenant.MaxUsers, a hard cap only Pillar sets; NULL = none).
CREATE FUNCTION admin.fn_TenantSeats (@TenantId INT)
RETURNS TABLE
AS
RETURN
    SELECT s.UsedSeats, s.IncludedSeats, s.ExtraSeatPrice,
           CASE WHEN s.IncludedSeats IS NOT NULL AND s.UsedSeats > s.IncludedSeats THEN s.UsedSeats - s.IncludedSeats ELSE 0 END AS ExtraSeats,
           CONVERT(DECIMAL(19,2), CASE WHEN s.IncludedSeats IS NOT NULL AND s.UsedSeats > s.IncludedSeats
                                       THEN (s.UsedSeats - s.IncludedSeats) * ISNULL(s.ExtraSeatPrice, 0) ELSE 0 END) AS ExtraSeatsMonthly,
           s.MaxUsers
    FROM (
        SELECT (SELECT COUNT(*) FROM sec.AppUser AS u
                WHERE u.TenantId = t.Id AND u.CanLogin = 1 AND u.Status <> 'DISABLED') AS UsedSeats,
               COALESCE(TRY_CONVERT(INT, io.Value), p.IncludedSeats) AS IncludedSeats,
               COALESCE(TRY_CONVERT(DECIMAL(19,2), po.Value), p.ExtraSeatPrice) AS ExtraSeatPrice,
               TRY_CONVERT(INT, mu.Value) AS MaxUsers
        FROM admin.Tenant AS t
        JOIN admin.[Plan] AS p ON p.Id = t.PlanId
        OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Seats.IncludedOverride') AS io
        OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Seats.ExtraPriceOverride') AS po
        OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Tenant.MaxUsers') AS mu
        WHERE t.Id = @TenantId
    ) AS s;
