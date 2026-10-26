-- The API logs each Pilo model call for the session tenant and user (ai.Generation). When a report that counts toward the quota
-- reaches 80% of the month's allowance, or all of it, billing.manage holders get PILO_USAGE_NEAR_LIMIT.
-- A RECEIPT read counts toward the allowance only when Pilo.ReceiptsCountTowardQuota is on (off by default: fair use, like Polish).
CREATE PROCEDURE ai.usp_Generation_Log
    @Feature            VARCHAR(15),
    @Model              VARCHAR(100),
    @InputTokens        INT = 0,
    @OutputTokens       INT = 0,
    @CostUsd            DECIMAL(19,6) = 0,
    @CountsTowardQuota  BIT = 0,
    @Succeeded          BIT = 1,
    @SavedReportId      INT = NULL,
    @GenerationId       BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')), @UserId INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Reports INT, @Included INT, @Title NVARCHAR(200);
    IF @TenantId IS NULL THROW 52216, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    IF @Feature = 'RECEIPT'
        SELECT @CountsTowardQuota = ISNULL(TRY_CONVERT(BIT, Value), 0) FROM admin.fn_Setting(@TenantId, NULL, 'Pilo.ReceiptsCountTowardQuota');

    INSERT INTO ai.Generation (TenantId, AppUserId, Feature, Model, InputTokens, OutputTokens, CostUsd, CountsTowardQuota, Succeeded, SavedReportId)
    VALUES (@TenantId, @UserId, @Feature, @Model, @InputTokens, @OutputTokens, @CostUsd, @CountsTowardQuota, @Succeeded, @SavedReportId);
    SET @GenerationId = SCOPE_IDENTITY();

    IF @CountsTowardQuota = 1
    BEGIN
        SELECT @Reports = Reports, @Included = IncludedReports
        FROM admin.fn_PiloUsage(@TenantId, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1));
        IF @Included > 0 AND (@Reports = CEILING(@Included * 0.8) OR @Reports = @Included)
        BEGIN
            SET @Title = CONCAT(N'Pilo: ', @Reports, N' of ', @Included, N' reports used this month');
            EXEC sec.usp_Notification_Raise @NotificationType = 'PILO_USAGE_NEAR_LIMIT', @EntityType = 'TENANT', @EntityId = @TenantId,
                 @Title = @Title;
        END;
    END;
END;
