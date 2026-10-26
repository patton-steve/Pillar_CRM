-- Seats for Admin > Billing & plan and the invite prompt ("This adds $12/month"): admin.fn_TenantSeats plus NextSeatPrice (what
-- one more login costs a month: 0 while under the included seats) and CanAddPaidSeat (the caller holds billing.manage; others
-- are refused past the included seats by sec.trg_AppUser_Rules).
CREATE PROCEDURE admin.usp_Seats_Get
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
    IF @TenantId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    SELECT s.UsedSeats, s.IncludedSeats, s.ExtraSeats, s.ExtraSeatPrice, s.ExtraSeatsMonthly, s.MaxUsers,
           CONVERT(DECIMAL(19,2), CASE WHEN s.IncludedSeats IS NOT NULL AND s.UsedSeats >= s.IncludedSeats
                                       THEN ISNULL(s.ExtraSeatPrice, 0) ELSE 0 END) AS NextSeatPrice,
           CONVERT(BIT, CASE WHEN EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage')) THEN 1 ELSE 0 END) AS CanAddPaidSeat
    FROM admin.fn_TenantSeats(@TenantId) AS s;
END;
