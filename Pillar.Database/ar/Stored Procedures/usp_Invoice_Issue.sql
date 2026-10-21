-- Issues a draft: refuses a billing profile with no billing contact or an invoice with no lines,
-- snapshots bill-to / terms / layout / remit from the profile (layout and remit fall back to the tenant defaults), sets InvoiceDate (default: tenant today) and DueDate,
-- assigns the invoice number, marks its time INVOICED, and accrues the platform fee - all in one transaction.
CREATE PROCEDURE ar.usp_Invoice_Issue
    @InvoiceId      INT,
    @InvoiceDate    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CAST(SESSION_CONTEXT(N'TenantId') AS INT),
            @UserId   INT = CAST(SESSION_CONTEXT(N'UserId') AS INT),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @ProfileId INT, @ContactId INT, @Number INT, @InvoiceNumber NVARCHAR(50),
            @SubTotal DECIMAL(19,2), @FeeRate DECIMAL(9,6), @FeeCap DECIMAL(19,2), @Fee DECIMAL(19,2);

    BEGIN TRAN;

    SELECT @ProfileId = i.BillingProfileId, @ContactId = bp.BillingContactId
    FROM ar.Invoice AS i WITH (UPDLOCK)
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId AND s.SystemCode = 'DRAFT'
    JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = i.TenantId AND bp.Id = i.BillingProfileId
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    IF @ProfileId IS NULL THROW 50611, N'Only draft invoices can be issued.', 1;
    IF @ContactId IS NULL THROW 50612, N'The billing profile has no billing contact. Add one before issuing.', 1;
    IF NOT EXISTS (SELECT 1 FROM ar.InvoiceEntry WHERE TenantId = @TenantId AND InvoiceId = @InvoiceId)
        THROW 50613, N'The invoice has no lines.', 1;

    IF @InvoiceDate IS NULL
        SELECT @InvoiceDate = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE t.TimeZoneId AS DATE)
        FROM admin.Tenant AS t WHERE t.Id = @TenantId;

    -- pick up the profile's current tax exemption, then recompute totals while still a draft
    UPDATE i SET TaxExempt = bp.TaxExempt
    FROM ar.Invoice AS i
    JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = i.TenantId AND bp.Id = i.BillingProfileId
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    EXEC ar.usp_Invoice_Recalculate @InvoiceId = @InvoiceId;
    EXEC admin.usp_NextNumber @TenantId = @TenantId, @SequenceKey = 'INVOICE', @Count = 1,
         @FirstValue = @Number OUTPUT, @Formatted = @InvoiceNumber OUTPUT;

    UPDATE i
    SET InvoiceNumber   = @InvoiceNumber,
        InvoiceStatusId = st.Id,
        InvoiceDate     = @InvoiceDate,
        DueDate         = DATEADD(DAY, pt.DueDays, @InvoiceDate),
        BillToContactId = c.Id,
        BillToName      = c.DisplayName,
        BillToEmail     = c.Email,
        BillToAddress   = CONCAT_WS(CHAR(13) + CHAR(10), a.Line1, a.Line2, a.Line3,
                                    CONCAT(a.City, CASE WHEN a.Region IS NOT NULL THEN N', ' + a.Region END,
                                           CASE WHEN a.PostalCode IS NOT NULL THEN N' ' + a.PostalCode END),
                                    CASE WHEN a.CountryCode <> 'US' THEN a.CountryCode END),
        ClientName      = cl.Name,
        InvoiceLayoutId = COALESCE(bp.InvoiceLayoutId, dl.Id),
        RemitProfileId  = COALESCE(bp.RemitProfileId, dr.Id),
        InvoiceNotes    = bp.InvoiceNotes,
        IssuedAt = @Now, IssuedBy = @UserId, ModifiedAt = @Now, ModifiedBy = @UserId,
        @SubTotal       = i.SubTotal
    FROM ar.Invoice AS i
    JOIN crm.ClientBillingProfile AS bp ON bp.TenantId = i.TenantId AND bp.Id = i.BillingProfileId
    JOIN crm.Contact AS c ON c.TenantId = bp.TenantId AND c.Id = bp.BillingContactId
    JOIN crm.Client AS cl ON cl.TenantId = i.TenantId AND cl.Id = i.ClientId
    JOIN lkp.PaymentTerm AS pt ON pt.TenantId = i.TenantId AND pt.Id = i.PaymentTermId
    JOIN lkp.InvoiceStatus AS st ON st.TenantId = i.TenantId AND st.SystemCode = 'ISSUED'
    LEFT JOIN crm.Address AS a ON a.TenantId = bp.TenantId AND a.Id = bp.BillingAddressId
    LEFT JOIN ar.InvoiceLayout AS dl ON dl.TenantId = i.TenantId AND dl.IsDefault = 1 AND dl.IsActive = 1
    LEFT JOIN admin.RemitProfile AS dr ON dr.TenantId = i.TenantId AND dr.IsDefault = 1 AND dr.IsActive = 1
    WHERE i.TenantId = @TenantId AND i.Id = @InvoiceId;

    UPDATE e
    SET TimeEntryStatusId = s.Id, ModifiedAt = @Now, ModifiedBy = @UserId
    FROM crm.TimeEntry AS e
    JOIN ar.InvoiceEntry AS l ON l.TenantId = e.TenantId AND l.Id = e.InvoiceEntryId
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.SystemCode = 'INVOICED'
    WHERE e.TenantId = @TenantId AND l.InvoiceId = @InvoiceId;

    -- platform fee: tenant overrides (hidden PLATFORM_ONLY settings), else the plan's rate and cap
    SELECT @FeeRate = COALESCE(TRY_CAST(f.Value AS DECIMAL(9,6)), p.FeeRate),
           @FeeCap  = COALESCE(TRY_CAST(fc.Value AS DECIMAL(19,2)), p.PerInvoiceCap)
    FROM admin.Tenant AS t
    JOIN admin.[Plan] AS p ON p.Id = t.PlanId
    OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Platform.FeeRateOverride') AS f
    OUTER APPLY admin.fn_Setting(t.Id, NULL, 'Platform.FeeCapOverride') AS fc
    WHERE t.Id = @TenantId;

    SET @Fee = ROUND(@SubTotal * @FeeRate, 2);
    IF @FeeCap IS NOT NULL AND @Fee > @FeeCap SET @Fee = @FeeCap;

    INSERT INTO admin.PlatformFee (TenantId, InvoiceId, FeeBaseAmount, FeeRate, FeeAmount)
    VALUES (@TenantId, @InvoiceId, @SubTotal, @FeeRate, @Fee);

    COMMIT;
END;
