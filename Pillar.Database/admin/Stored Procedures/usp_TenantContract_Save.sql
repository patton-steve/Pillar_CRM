-- Saves a tenant's contract terms from the back office Contract & billing tab (Pillar staff, handoff 26). A reason is required
-- and audited. Adds a row from @EffectiveFrom (default today; a later date is scheduled). Saving again for the same date
-- replaces that row. NULL parameters copy the value from the contract in force on @EffectiveFrom, so the tab can send only what
-- changed; @Clear* = 1 empties a nullable field instead. The signed contract is a link (@DocumentUrl) or a file
-- (@DocumentContent, up to 10 MB, with its name and type); when neither is passed the previous one is kept.
CREATE PROCEDURE admin.usp_TenantContract_Save
    @TenantId               INT,
    @EffectiveFrom          DATE = NULL,
    @Term                   VARCHAR(10) = NULL,
    @StartDate              DATE = NULL,
    @RenewalDate            DATE = NULL,
    @Prepaid                BIT = NULL,
    @PrepaidThrough         DATE = NULL,
    @DiscountPct            DECIMAL(5,4) = NULL,
    @CommittedSeats         INT = NULL,
    @ClearCommittedSeats    BIT = 0,
    @Notes                  NVARCHAR(2000) = NULL,
    @DocumentUrl            NVARCHAR(500) = NULL,
    @DocumentName           NVARCHAR(200) = NULL,
    @DocumentContentType    VARCHAR(100) = NULL,
    @DocumentContent        VARBINARY(MAX) = NULL,
    @ClearDocument          BIT = 0,
    @Reason                 NVARCHAR(500) = NULL,
    @ContractId             INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME(),
            @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')), @PrevId INT, @Change NVARCHAR(MAX), @Summary NVARCHAR(400);
    SET @EffectiveFrom = ISNULL(@EffectiveFrom, @Today);
    IF @Term IS NOT NULL AND @Term <> 'MONTHLY' AND @Term <> 'ANNUAL' THROW 52610, N'The term is MONTHLY or ANNUAL.', 1;
    IF @DiscountPct < 0 OR @DiscountPct > 1 THROW 52611, N'The discount is between 0 and 1 (0.10 = 10%).', 1;
    IF @CommittedSeats < 0 THROW 52612, N'Committed seats can''t be negative.', 1;
    IF @DocumentContent IS NOT NULL AND (DATALENGTH(@DocumentContent) > 10485760 OR NULLIF(LTRIM(@DocumentName), N'') IS NULL)
        THROW 52613, N'Attach the signed contract as a file of up to 10 MB, with its name.', 1;

    SELECT TOP (1) @PrevId = Id FROM admin.TenantContract
    WHERE TenantId = @TenantId AND SupersededAt IS NULL AND EffectiveFrom <= @EffectiveFrom
    ORDER BY EffectiveFrom DESC, Id DESC;

    BEGIN TRAN;
    UPDATE admin.TenantContract SET SupersededAt = @Now, SupersededBy = @UserId
    WHERE TenantId = @TenantId AND EffectiveFrom = @EffectiveFrom AND SupersededAt IS NULL;

    INSERT INTO admin.TenantContract (TenantId, EffectiveFrom, Term, StartDate, RenewalDate, Prepaid, PrepaidThrough, DiscountPct,
                                      CommittedSeats, Notes, DocumentUrl, DocumentName, DocumentContentType, DocumentContent, Reason)
    SELECT @TenantId, @EffectiveFrom,
           COALESCE(@Term, p.Term, 'MONTHLY'),
           COALESCE(@StartDate, p.StartDate, @EffectiveFrom),
           COALESCE(@RenewalDate, p.RenewalDate),
           COALESCE(@Prepaid, p.Prepaid, 0),
           CASE WHEN COALESCE(@Prepaid, p.Prepaid, 0) = 0 THEN NULL ELSE COALESCE(@PrepaidThrough, p.PrepaidThrough) END,
           COALESCE(@DiscountPct, p.DiscountPct, 0),
           CASE WHEN @ClearCommittedSeats = 1 THEN NULL ELSE COALESCE(@CommittedSeats, p.CommittedSeats) END,
           COALESCE(@Notes, p.Notes),
           CASE WHEN @ClearDocument = 1 THEN NULL WHEN @DocumentUrl IS NOT NULL OR @DocumentContent IS NOT NULL THEN @DocumentUrl ELSE p.DocumentUrl END,
           CASE WHEN @ClearDocument = 1 THEN NULL WHEN @DocumentContent IS NOT NULL THEN @DocumentName
                WHEN @DocumentUrl IS NOT NULL THEN NULL ELSE p.DocumentName END,
           CASE WHEN @ClearDocument = 1 THEN NULL WHEN @DocumentContent IS NOT NULL THEN @DocumentContentType
                WHEN @DocumentUrl IS NOT NULL THEN NULL ELSE p.DocumentContentType END,
           CASE WHEN @ClearDocument = 1 THEN NULL WHEN @DocumentContent IS NOT NULL THEN @DocumentContent
                WHEN @DocumentUrl IS NOT NULL THEN NULL ELSE p.DocumentContent END,
           @Reason
    FROM (SELECT 1 AS One) AS x
    LEFT JOIN admin.TenantContract AS p ON p.Id = @PrevId;
    SET @ContractId = SCOPE_IDENTITY();

    SET @Change = (SELECT EffectiveFrom, Term, StartDate, RenewalDate, Prepaid, PrepaidThrough, DiscountPct, CommittedSeats, DocumentUrl, DocumentName
                   FROM admin.TenantContract WHERE Id = @ContractId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
    SET @Summary = CONCAT(N'Contract terms from ', CONVERT(CHAR(10), @EffectiveFrom, 23));
    EXEC admin.usp_PlatformAudit_Write @Action = 'CONTRACT_SAVE', @TenantId = @TenantId, @EntityType = 'CONTRACT',
         @EntityKey = @ContractId, @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    COMMIT;
END;
