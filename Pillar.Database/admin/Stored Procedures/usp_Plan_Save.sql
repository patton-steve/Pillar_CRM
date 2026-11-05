-- Creates or edits a plan from the back office plan editor (Pillar staff, handoff 26). A reason is required and audited.
--   Name, SortOrder, IsActive, IsPublic and IsDefault change at once (NULL keeps the current value). A private plan (IsPublic = 0)
--   is a custom deal: tenants can't pick it, only Pillar assigns it (admin.usp_Tenant_SetPlan). The default plan must be
--   public and active.
--   Prices and limits: pass @FeeRate and every other priced parameter together (the editor's full set; NULL in a nullable one
--   means none or no cap). They become a new version (admin.PlanVersion) from @EffectiveFrom (default: today for a new plan,
--   the 1st of next month for an existing one; never before today). A version dated today applies at once; a later one is
--   scheduled and applied by the daily job. Saving again for the same date replaces that scheduled version.
--   @ApplyTo NEW_ONLY grandfathers the plan's current tenants: their terms are copied into a private plan (Code + _G + yyMM of
--   @EffectiveFrom, with the plan's features and version history) and they move onto it today, so only new tenants get the new
--   version. ALL (default) moves everyone on the plan to the new version on its date.
-- Returns the plan id, the version id (NULL when no prices were passed) and the grandfathered plan's id.
CREATE PROCEDURE admin.usp_Plan_Save
    @PlanId                 INT = NULL OUTPUT,
    @Code                   VARCHAR(20) = NULL,
    @Name                   NVARCHAR(100) = NULL,
    @SortOrder              INT = NULL,
    @IsActive               BIT = NULL,
    @IsPublic               BIT = NULL,
    @IsDefault              BIT = NULL,
    @FeeRate                DECIMAL(9,6) = NULL,
    @PerInvoiceCap          DECIMAL(19,2) = NULL,
    @MonthlyMinimum         DECIMAL(19,2) = NULL,
    @FeePerHeadCap          DECIMAL(19,2) = NULL,
    @ExcludeExpensesFromFee BIT = NULL,
    @MonthlyPrice           DECIMAL(19,2) = NULL,
    @IncludedSeats          INT = NULL,
    @ExtraSeatPrice         DECIMAL(19,2) = NULL,
    @MaxSeats               INT = NULL,
    @IncludedAiReports      INT = NULL,
    @AiOveragePrice         DECIMAL(19,2) = NULL,
    @IncludedAiSearches     INT = NULL,
    @EffectiveFrom          DATE = NULL,
    @ApplyTo                VARCHAR(10) = 'ALL',
    @Reason                 NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME(), @IsNew BIT = IIF(@PlanId IS NULL, 1, 0),
            @VersionId INT, @GrandPlanId INT, @GrandCode VARCHAR(20), @OldCode VARCHAR(20), @Moved INT = 0,
            @Change NVARCHAR(MAX), @Summary NVARCHAR(400), @HasPrices BIT = IIF(@FeeRate IS NOT NULL, 1, 0);

    SET @ApplyTo = UPPER(ISNULL(@ApplyTo, 'ALL'));
    IF @ApplyTo <> 'ALL' AND @ApplyTo <> 'NEW_ONLY' THROW 52601, N'Apply the change to ALL tenants or NEW_ONLY.', 1;
    IF @IsNew = 0 AND NOT EXISTS (SELECT 1 FROM admin.[Plan] WHERE Id = @PlanId) THROW 52204, N'Unknown plan.', 1;
    IF @IsNew = 1 AND (@Code IS NULL OR NULLIF(LTRIM(@Name), N'') IS NULL OR @HasPrices = 0)
        THROW 52602, N'A new plan needs a code, a name and its prices.', 1;
    IF @Code IS NOT NULL AND (@Code LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN OR LEN(@Code) < 2)
        THROW 52602, N'Plan codes use capital letters, digits and _.', 1;
    IF @IsNew = 0 AND @Code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admin.[Plan] WHERE Id = @PlanId AND Code = @Code)
        THROW 52602, N'A plan''s code can''t change once it exists.', 1;
    IF @Code IS NOT NULL AND EXISTS (SELECT 1 FROM admin.[Plan] WHERE Code = @Code AND (@PlanId IS NULL OR Id <> @PlanId))
        THROW 52602, N'Another plan already uses that code.', 1;
    IF @HasPrices = 1 AND (@FeeRate < 0 OR @FeeRate >= 1 OR ISNULL(@MonthlyPrice, -1) < 0 OR @ExcludeExpensesFromFee IS NULL
                           OR @IncludedAiReports IS NULL OR @IncludedAiSearches IS NULL OR @IncludedAiReports < 0 OR @IncludedAiSearches < 0
                           OR @IncludedSeats < 1 OR @MaxSeats < 1 OR @ExtraSeatPrice < 0 OR @AiOveragePrice < 0 OR @FeePerHeadCap < 0
                           OR @PerInvoiceCap < 0 OR @MonthlyMinimum < 0 OR (@MaxSeats IS NOT NULL AND @IncludedSeats > @MaxSeats))
        THROW 52603, N'Check the prices: the fee rate is 0 to under 1, amounts and counts can''t be negative, and included seats can''t exceed max seats.', 1;
    SET @EffectiveFrom = COALESCE(@EffectiveFrom, IIF(@IsNew = 1, @Today, DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1))));
    IF @HasPrices = 1 AND @EffectiveFrom < @Today THROW 52603, N'A price change can''t start in the past.', 1;
    IF @ApplyTo = 'NEW_ONLY' AND (@IsNew = 1 OR @HasPrices = 0) THROW 52601, N'Grandfathering needs a price change to an existing plan.', 1;

    BEGIN TRAN;

    IF @IsNew = 1
    BEGIN
        INSERT INTO admin.[Plan] (Code, Name, FeeRate, PerInvoiceCap, MonthlyMinimum, IsDefault, IsActive, MonthlyPrice, IncludedSeats,
                                  ExtraSeatPrice, IncludedAiReports, AiOveragePrice, SortOrder, IncludedAiSearches, FeePerHeadCap,
                                  ExcludeExpensesFromFee, IsPublic, MaxSeats)
        VALUES (@Code, @Name, @FeeRate, @PerInvoiceCap, @MonthlyMinimum, 0, ISNULL(@IsActive, 1), @MonthlyPrice, @IncludedSeats,
                @ExtraSeatPrice, @IncludedAiReports, @AiOveragePrice, ISNULL(@SortOrder, 100), @IncludedAiSearches, @FeePerHeadCap,
                @ExcludeExpensesFromFee, ISNULL(@IsPublic, 1), @MaxSeats);
        SET @PlanId = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE admin.[Plan]
        SET Name = COALESCE(NULLIF(LTRIM(@Name), N''), Name), SortOrder = COALESCE(@SortOrder, SortOrder),
            IsActive = COALESCE(@IsActive, IsActive), IsPublic = COALESCE(@IsPublic, IsPublic)
        WHERE Id = @PlanId;

    IF @IsDefault = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM admin.[Plan] WHERE Id = @PlanId AND (IsPublic = 0 OR IsActive = 0))
            THROW 52604, N'The default plan must be public and active.', 1;
        UPDATE admin.[Plan] SET IsDefault = 0 WHERE IsDefault = 1 AND Id <> @PlanId;
        UPDATE admin.[Plan] SET IsDefault = 1 WHERE Id = @PlanId;
    END
    ELSE IF EXISTS (SELECT 1 FROM admin.[Plan] WHERE Id = @PlanId AND IsDefault = 1 AND (IsPublic = 0 OR IsActive = 0 OR @IsDefault = 0))
        THROW 52604, N'The default plan must be public and active. Make another plan the default first.', 1;

    -- grandfather: the current tenants keep today's terms on a private copy
    IF @ApplyTo = 'NEW_ONLY'
    BEGIN
        SELECT @OldCode = Code FROM admin.[Plan] WHERE Id = @PlanId;
        SET @GrandCode = CONCAT(LEFT(@OldCode, 13), '_G', FORMAT(@EffectiveFrom, 'yyMM'));
        IF EXISTS (SELECT 1 FROM admin.[Plan] WHERE Code = @GrandCode)
            THROW 52605, N'This plan was already grandfathered for that month. Cancel or edit that version instead.', 1;

        INSERT INTO admin.[Plan] (Code, Name, FeeRate, PerInvoiceCap, MonthlyMinimum, IsDefault, IsActive, MonthlyPrice, IncludedSeats,
                                  ExtraSeatPrice, IncludedAiReports, AiOveragePrice, SortOrder, IncludedAiSearches, FeePerHeadCap,
                                  ExcludeExpensesFromFee, IsPublic, MaxSeats)
        SELECT @GrandCode, LEFT(CONCAT(Name, N' (before ', FORMAT(@EffectiveFrom, 'MMM yyyy', 'en-US'), N')'), 100),
               FeeRate, PerInvoiceCap, MonthlyMinimum, 0, 1, MonthlyPrice, IncludedSeats, ExtraSeatPrice, IncludedAiReports,
               AiOveragePrice, SortOrder + 1, IncludedAiSearches, FeePerHeadCap, ExcludeExpensesFromFee, 0, MaxSeats
        FROM admin.[Plan] WHERE Id = @PlanId;
        SET @GrandPlanId = SCOPE_IDENTITY();

        -- the version history up to the new date (or today's terms as a baseline)
        INSERT INTO admin.PlanVersion (PlanId, EffectiveFrom, FeeRate, PerInvoiceCap, MonthlyMinimum, FeePerHeadCap, ExcludeExpensesFromFee,
                                       MonthlyPrice, IncludedSeats, ExtraSeatPrice, MaxSeats, IncludedAiReports, AiOveragePrice,
                                       IncludedAiSearches, Reason, AppliedAt)
        SELECT @GrandPlanId, v.EffectiveFrom, v.FeeRate, v.PerInvoiceCap, v.MonthlyMinimum, v.FeePerHeadCap, v.ExcludeExpensesFromFee,
               v.MonthlyPrice, v.IncludedSeats, v.ExtraSeatPrice, v.MaxSeats, v.IncludedAiReports, v.AiOveragePrice, v.IncludedAiSearches,
               v.Reason, v.AppliedAt
        FROM admin.PlanVersion AS v
        WHERE v.PlanId = @PlanId AND v.CancelledAt IS NULL AND v.EffectiveFrom < @EffectiveFrom;
        IF @@ROWCOUNT = 0
            INSERT INTO admin.PlanVersion (PlanId, EffectiveFrom, FeeRate, PerInvoiceCap, MonthlyMinimum, FeePerHeadCap, ExcludeExpensesFromFee,
                                           MonthlyPrice, IncludedSeats, ExtraSeatPrice, MaxSeats, IncludedAiReports, AiOveragePrice,
                                           IncludedAiSearches, Reason, AppliedAt)
            SELECT @GrandPlanId, '2000-01-01', FeeRate, PerInvoiceCap, MonthlyMinimum, FeePerHeadCap, ExcludeExpensesFromFee, MonthlyPrice,
                   IncludedSeats, ExtraSeatPrice, MaxSeats, IncludedAiReports, AiOveragePrice, IncludedAiSearches, @Reason, @Now
            FROM admin.[Plan] WHERE Id = @PlanId;

        INSERT INTO admin.PlanSettingDefault (PlanId, SettingKey, Value)
        SELECT @GrandPlanId, SettingKey, Value FROM admin.PlanSettingDefault WHERE PlanId = @PlanId;

        -- move the tenants (same terms, so nothing is prorated) and any downgrade they have waiting
        INSERT INTO admin.TenantPlanChange (TenantId, FromPlanId, ToPlanId, Kind, Status, EffectiveDate, AppliedAt, Note)
        SELECT t.Id, @PlanId, @GrandPlanId, 'PLATFORM', 'APPLIED', @Today, @Now, LEFT(CONCAT(N'Grandfathered: ', @Reason), 500)
        FROM admin.Tenant AS t WHERE t.PlanId = @PlanId;
        SET @Moved = @@ROWCOUNT;
        UPDATE c SET FromPlanId = @GrandPlanId
        FROM admin.TenantPlanChange AS c
        JOIN admin.Tenant AS t ON t.Id = c.TenantId
        WHERE t.PlanId = @PlanId AND c.Status = 'PENDING' AND c.FromPlanId = @PlanId AND c.ToPlanId <> @GrandPlanId;
        UPDATE admin.Tenant SET PlanId = @GrandPlanId WHERE PlanId = @PlanId;

        SET @Change = (SELECT @PlanId AS fromPlanId, @GrandPlanId AS toPlanId, @Moved AS tenants FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SET @Summary = CONCAT(N'Grandfathered ', @Moved, N' tenant(s) from ', @OldCode, N' onto ', @GrandCode);
        EXEC admin.usp_PlatformAudit_Write @Action = 'PLAN_GRANDFATHER', @EntityType = 'PLAN', @EntityKey = @GrandCode,
             @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    END;

    IF @HasPrices = 1
    BEGIN
        UPDATE admin.PlanVersion SET CancelledAt = @Now
        WHERE PlanId = @PlanId AND EffectiveFrom = @EffectiveFrom AND CancelledAt IS NULL;
        INSERT INTO admin.PlanVersion (PlanId, EffectiveFrom, FeeRate, PerInvoiceCap, MonthlyMinimum, FeePerHeadCap, ExcludeExpensesFromFee,
                                       MonthlyPrice, IncludedSeats, ExtraSeatPrice, MaxSeats, IncludedAiReports, AiOveragePrice,
                                       IncludedAiSearches, Reason, AppliedAt)
        VALUES (@PlanId, @EffectiveFrom, @FeeRate, @PerInvoiceCap, @MonthlyMinimum, @FeePerHeadCap, @ExcludeExpensesFromFee, @MonthlyPrice,
                @IncludedSeats, @ExtraSeatPrice, @MaxSeats, @IncludedAiReports, @AiOveragePrice, @IncludedAiSearches, @Reason,
                IIF(@EffectiveFrom <= @Today, @Now, NULL));
        SET @VersionId = SCOPE_IDENTITY();

        IF @EffectiveFrom <= @Today
            UPDATE admin.[Plan]
            SET FeeRate = @FeeRate, PerInvoiceCap = @PerInvoiceCap, MonthlyMinimum = @MonthlyMinimum, FeePerHeadCap = @FeePerHeadCap,
                ExcludeExpensesFromFee = @ExcludeExpensesFromFee, MonthlyPrice = @MonthlyPrice, IncludedSeats = @IncludedSeats,
                ExtraSeatPrice = @ExtraSeatPrice, MaxSeats = @MaxSeats, IncludedAiReports = @IncludedAiReports,
                AiOveragePrice = @AiOveragePrice, IncludedAiSearches = @IncludedAiSearches
            WHERE Id = @PlanId;
    END;

    SET @Change = (SELECT p.Code, p.Name, p.IsActive, p.IsPublic, p.IsDefault, p.SortOrder, @EffectiveFrom AS effectiveFrom, @ApplyTo AS applyTo,
                          v.FeeRate, v.PerInvoiceCap, v.MonthlyMinimum, v.FeePerHeadCap, v.ExcludeExpensesFromFee, v.MonthlyPrice,
                          v.IncludedSeats, v.ExtraSeatPrice, v.MaxSeats, v.IncludedAiReports, v.AiOveragePrice, v.IncludedAiSearches
                   FROM admin.[Plan] AS p LEFT JOIN admin.PlanVersion AS v ON v.Id = @VersionId
                   WHERE p.Id = @PlanId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
    SELECT @Summary = CONCAT(IIF(@IsNew = 1, N'Created plan ', N'Edited plan '), Code,
                             IIF(@HasPrices = 1, CONCAT(N', prices from ', CONVERT(CHAR(10), @EffectiveFrom, 23)), N''))
    FROM admin.[Plan] WHERE Id = @PlanId;
    SELECT @OldCode = Code FROM admin.[Plan] WHERE Id = @PlanId;
    EXEC admin.usp_PlatformAudit_Write @Action = 'PLAN_SAVE', @EntityType = 'PLAN', @EntityKey = @OldCode,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;

    COMMIT;

    SELECT @PlanId AS PlanId, @VersionId AS PlanVersionId, @GrandPlanId AS GrandfatheredPlanId, @Moved AS TenantsGrandfathered;
END;
