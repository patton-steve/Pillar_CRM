-- Adds a one-time charge to a tenant (Pillar staff, handoff 26): Kind ONBOARDING, IMPORT, CUSTOM_RDL or OTHER, with an amount
-- and the description the statement prints. BillOn NEXT_STATEMENT (default) bills it as a SERVICE line on the statement for
-- @ChargeDate's month (default today); CHARGE_NOW leaves it for the API to charge the card on file now and report back with
-- admin.usp_PlatformCharge_RecordPayment. A reason is required and audited.
CREATE PROCEDURE admin.usp_PlatformCharge_Add
    @TenantId       INT,
    @Kind           VARCHAR(12),
    @Description    NVARCHAR(200),
    @Amount         DECIMAL(19,2),
    @BillOn         VARCHAR(15) = 'NEXT_STATEMENT',
    @ChargeDate     DATE = NULL,
    @Reason         NVARCHAR(500),
    @ChargeId       INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(CAST(SESSION_CONTEXT(N'IsPlatformAdmin') AS BIT), 0) = 0 THROW 52201, N'Only Pillar staff can do this.', 1;
    IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL THROW 52205, N'A reason is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId) THROW 52202, N'Unknown tenant.', 1;
    IF @Kind IS NULL OR (@Kind <> 'ONBOARDING' AND @Kind <> 'IMPORT' AND @Kind <> 'CUSTOM_RDL' AND @Kind <> 'OTHER')
        THROW 52620, N'The kind is ONBOARDING, IMPORT, CUSTOM_RDL or OTHER.', 1;
    IF NULLIF(LTRIM(@Description), N'') IS NULL OR ISNULL(@Amount, 0) <= 0
        THROW 52621, N'A charge needs a description and an amount above 0.', 1;
    SET @BillOn = ISNULL(@BillOn, 'NEXT_STATEMENT');
    IF @BillOn <> 'NEXT_STATEMENT' AND @BillOn <> 'CHARGE_NOW' THROW 52622, N'Bill it on the NEXT_STATEMENT or CHARGE_NOW.', 1;
    IF @BillOn = 'CHARGE_NOW' AND NOT EXISTS (SELECT 1 FROM admin.TenantPaymentMethod WHERE TenantId = @TenantId AND IsDefault = 1 AND IsActive = 1)
        THROW 52623, N'The company has no card on file to charge now. Put it on the next statement instead.', 1;

    DECLARE @Change NVARCHAR(MAX), @Summary NVARCHAR(400);
    BEGIN TRAN;
    INSERT INTO admin.PlatformCharge (TenantId, Kind, Description, Amount, BillOn, ChargeDate, Reason)
    VALUES (@TenantId, @Kind, @Description, @Amount, @BillOn, ISNULL(@ChargeDate, CAST(SYSUTCDATETIME() AS DATE)), @Reason);
    SET @ChargeId = SCOPE_IDENTITY();
    SET @Change = (SELECT Kind, Description, Amount, BillOn, ChargeDate FROM admin.PlatformCharge WHERE Id = @ChargeId
                   FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SET @Summary = CONCAT(N'One-time charge ', FORMAT(@Amount, 'C', 'en-US'), N': ', LEFT(@Description, 100));
    EXEC admin.usp_PlatformAudit_Write @Action = 'CHARGE_ADD', @TenantId = @TenantId, @EntityType = 'CHARGE', @EntityKey = @ChargeId,
         @Summary = @Summary, @Reason = @Reason, @ChangeJson = @Change;
    COMMIT;
END;
