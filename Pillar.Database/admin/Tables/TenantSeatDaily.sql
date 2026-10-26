-- Seats in use per tenant per day (UTC), for the SEATS line on the monthly platform statement (Steve 2026-10-22: billed on the
-- month's peak, not prorated). sec.trg_AppUser_Rules keeps today's row current whenever a login is added, enabled or disabled:
-- PeakSeats is the day's highest count, EndSeats the count after the latest change. A month's peak is the highest PeakSeats in
-- the month, or the EndSeats of the latest earlier row (the count the month started with), whichever is higher.
-- A seat is a user with CanLogin = 1 who isn't DISABLED (INVITED counts); no-login billable people don't count.
CREATE TABLE admin.TenantSeatDaily
(
    TenantId        INT             NOT NULL,
    SeatDate        DATE            NOT NULL,
    PeakSeats       INT             NOT NULL,
    EndSeats        INT             NOT NULL,
    CONSTRAINT PK_TenantSeatDaily PRIMARY KEY CLUSTERED (TenantId, SeatDate),
    CONSTRAINT FK_TenantSeatDaily_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
