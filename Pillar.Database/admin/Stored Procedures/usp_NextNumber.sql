-- Reserves @Count consecutive numbers for (@TenantId, @SequenceKey) and returns the first,
-- plus the first number formatted per the sequence's Prefix / IncludeYear / PadLength.
-- Creates the sequence on first use, unformatted except BILL- / EXP- prefixes for 'BILL' and 'EXPENSE'. Call inside the transaction that uses the number.
-- The year for IncludeYear / YEARLY reset is the tenant's local year.
CREATE PROCEDURE admin.usp_NextNumber
    @TenantId       INT,
    @SequenceKey    VARCHAR(30),
    @Count          INT = 1,
    @FirstValue     INT OUTPUT,
    @Formatted      NVARCHAR(50) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Count < 1 THROW 50001, N'@Count must be at least 1.', 1;

    DECLARE @Year SMALLINT, @Prefix NVARCHAR(20), @IncludeYear BIT, @Pad TINYINT;

    SELECT @Year = YEAR(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId)
    FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    BEGIN TRAN;

    UPDATE s
    SET @FirstValue  = CASE WHEN s.ResetPolicy = 'YEARLY' AND s.CurrentYear <> @Year THEN 1 ELSE s.NextValue END,
        NextValue    = CASE WHEN s.ResetPolicy = 'YEARLY' AND s.CurrentYear <> @Year THEN 1 ELSE s.NextValue END + @Count,
        CurrentYear  = @Year,
        ModifiedAt   = SYSUTCDATETIME(),
        @Prefix      = s.Prefix,
        @IncludeYear = s.IncludeYear,
        @Pad         = s.PadLength
    FROM admin.NumberSequence AS s WITH (UPDLOCK, HOLDLOCK)
    WHERE s.TenantId = @TenantId AND s.SequenceKey = @SequenceKey;

    IF @@ROWCOUNT = 0
    BEGIN
        -- HOLDLOCK above holds a key-range lock, so a concurrent first caller waits here rather than duplicating.
        -- vendor bills and expense reports share ap.Bill's unique number, so their sequences get distinct prefixes
        SET @Prefix = CASE @SequenceKey WHEN 'BILL' THEN N'BILL-' WHEN 'EXPENSE' THEN N'EXP-' END;
        INSERT INTO admin.NumberSequence (TenantId, SequenceKey, Prefix, NextValue, CurrentYear, ModifiedAt)
        VALUES (@TenantId, @SequenceKey, @Prefix, 1 + @Count, @Year, SYSUTCDATETIME());
        SELECT @FirstValue = 1, @IncludeYear = 0, @Pad = 0;
    END;

    COMMIT;

    SET @Formatted = CONCAT(@Prefix,
                            CASE WHEN @IncludeYear = 1 THEN CONCAT(@Year, '-') END,
                            CASE WHEN LEN(@FirstValue) < @Pad
                                 THEN RIGHT(REPLICATE('0', @Pad) + CAST(@FirstValue AS VARCHAR(10)), @Pad)
                                 ELSE CAST(@FirstValue AS VARCHAR(10)) END);
END;
