-- Saves a Pilo report from the Reports page, or edits one (name, parameters, sharing). Needs Feature.Pilo.
-- Anyone saves their own; IsShared = 1 (a company report) needs report.share. A company report can be edited by its
-- owner or anyone with report.share; a personal one only by its owner.
-- Limits: Pilo.SavedReportsPerUser personal reports per person, Pilo.CompanyReports company reports per tenant.
-- At the limit the save fails (51615/51616); the UI asks which one to remove and calls again with
-- @ReplaceSavedReportId, which deletes that report in the same transaction. Errors 51613-51619.
CREATE PROCEDURE admin.usp_SavedReport_Save
    @SavedReportId          INT = NULL OUTPUT,
    @Name                   NVARCHAR(100) = NULL,
    @Prompt                 NVARCHAR(2000) = NULL,
    @Definition             NVARCHAR(MAX) = NULL,
    @ParameterJson          NVARCHAR(MAX) = NULL,
    @IsShared               BIT = NULL,
    @ReplaceSavedReportId   INT = NULL,
    @RenderType             VARCHAR(30) = NULL,    -- "Show it as"; NULL keeps the current one (new: Pilo chose)
    @ClearRenderType        BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @Pilo BIT, @CanShare BIT = 0, @OldOwner INT, @OldShared BIT,
            @PersonalLimit INT, @CompanyLimit INT, @Count INT, @Msg NVARCHAR(400);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 51613, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;
    SELECT @Pilo = ISNULL(TRY_CONVERT(BIT, Value), 0) FROM admin.fn_Setting(@TenantId, NULL, 'Feature.Pilo');
    IF ISNULL(@Pilo, 0) = 0 THROW 51614, N'Saving AI reports is part of the AI Powered plans.', 1;
    IF EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'report.share')) SET @CanShare = 1;
    SELECT @PersonalLimit = ISNULL(TRY_CONVERT(INT, Value), 0) FROM admin.fn_Setting(@TenantId, NULL, 'Pilo.SavedReportsPerUser');
    SELECT @CompanyLimit  = ISNULL(TRY_CONVERT(INT, Value), 0) FROM admin.fn_Setting(@TenantId, NULL, 'Pilo.CompanyReports');

    BEGIN TRAN;

    IF @SavedReportId IS NOT NULL
    BEGIN
        SELECT @OldOwner = OwnerUserId, @OldShared = IsShared FROM admin.SavedReport WITH (UPDLOCK)
        WHERE TenantId = @TenantId AND Id = @SavedReportId AND DeletedAt IS NULL;
        IF @OldOwner IS NULL THROW 51617, N'Saved report not found.', 1;
        IF @OldOwner <> @UserId AND NOT (@OldShared = 1 AND @CanShare = 1)
            THROW 51618, N'You can only change your own reports.', 1;
    END;
    SET @IsShared = COALESCE(@IsShared, @OldShared, 0);
    IF @IsShared = 1 AND ISNULL(@OldShared, 0) = 0 AND @CanShare = 0
        THROW 51618, N'You need permission to share reports with the company.', 1;

    IF @RenderType IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admin.ReportRenderType WHERE Code = @RenderType AND IsActive = 1)
        THROW 51617, N'Unknown chart type.', 1;

    IF @ReplaceSavedReportId IS NOT NULL
    BEGIN
        IF @ReplaceSavedReportId = @SavedReportId THROW 51619, N'Pick a different report to replace.', 1;
        UPDATE admin.SavedReport SET DeletedAt = @Now, ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @ReplaceSavedReportId AND DeletedAt IS NULL
          AND (OwnerUserId = @UserId OR (IsShared = 1 AND @CanShare = 1));
        IF @@ROWCOUNT = 0 THROW 51619, N'The report to replace was not found, or is not yours to remove.', 1;
    END;

    -- limits apply when a report is added to a list (new, or moved between personal and company)
    IF @IsShared = 0 AND (@SavedReportId IS NULL OR @OldShared = 1)
    BEGIN
        SELECT @Count = COUNT(*) FROM admin.SavedReport
        WHERE TenantId = @TenantId AND OwnerUserId = ISNULL(@OldOwner, @UserId) AND IsShared = 0 AND DeletedAt IS NULL;
        IF @Count >= @PersonalLimit
        BEGIN
            SET @Msg = CONCAT(N'Your plan allows ', @PersonalLimit, N' saved AI reports. Pick one to replace.');
            THROW 51615, @Msg, 1;
        END;
    END;
    IF @IsShared = 1 AND ISNULL(@OldShared, 0) = 0
    BEGIN
        IF @CompanyLimit = 0 THROW 51616, N'Company AI reports are part of the Enterprise plan.', 1;
        SELECT @Count = COUNT(*) FROM admin.SavedReport WITH (UPDLOCK, HOLDLOCK)
        WHERE TenantId = @TenantId AND IsShared = 1 AND DeletedAt IS NULL;
        IF @Count >= @CompanyLimit
        BEGIN
            SET @Msg = CONCAT(N'Your plan allows ', @CompanyLimit, N' company AI reports. Pick one to replace.');
            THROW 51616, @Msg, 1;
        END;
    END;

    IF @SavedReportId IS NULL
    BEGIN
        IF NULLIF(LTRIM(@Name), N'') IS NULL OR NULLIF(LTRIM(@Prompt), N'') IS NULL OR ISJSON(@Definition) <> 1
            THROW 51617, N'A saved report needs a name, the prompt and the report definition.', 1;
        IF @ParameterJson IS NOT NULL AND ISJSON(@ParameterJson) <> 1 THROW 51617, N'Parameters must be JSON.', 1;
        INSERT INTO admin.SavedReport (TenantId, OwnerUserId, Name, Prompt, Definition, ParameterJson, IsShared, RenderType)
        VALUES (@TenantId, @UserId, @Name, @Prompt, @Definition, @ParameterJson, @IsShared, @RenderType);
        SET @SavedReportId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        IF @ParameterJson IS NOT NULL AND ISJSON(@ParameterJson) <> 1 THROW 51617, N'Parameters must be JSON.', 1;
        IF @Definition IS NOT NULL AND ISJSON(@Definition) <> 1 THROW 51617, N'The report definition must be JSON.', 1;
        UPDATE admin.SavedReport
        SET Name = COALESCE(NULLIF(LTRIM(@Name), N''), Name), Prompt = COALESCE(NULLIF(LTRIM(@Prompt), N''), Prompt),
            Definition = COALESCE(@Definition, Definition), ParameterJson = COALESCE(@ParameterJson, ParameterJson),
            IsShared = @IsShared,
            RenderType = CASE WHEN @ClearRenderType = 1 THEN NULL ELSE COALESCE(@RenderType, RenderType) END, ModifiedAt = @Now, ModifiedBy = @UserId
        WHERE TenantId = @TenantId AND Id = @SavedReportId;
    END;

    COMMIT;
END;
