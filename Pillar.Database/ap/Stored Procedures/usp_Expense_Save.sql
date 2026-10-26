-- Time > My expenses quick-add row (Steve 2026-10-22: expenses go in weekly with the timesheet). Adds, edits or deletes
-- (@Delete = 1) one expense line on the person's expense report for the timesheet week that covers @ExpenseDate. The
-- week's timesheet and report are created with its first expense (report numbered from 'EXPENSE', BillDate = week end).
-- Needs expense.submit; someone else's expenses (@ForUserId) need time.enter_others. New reports need Feature.ExpenseReports
-- (ap.trg_Bill_ExpenseReportFlag). Only a DRAFT report can change: once the week is submitted it waits until it is
-- approved or sent back. Changing the date to another week moves the line to that week's report.
-- Amount: a category with a UnitRate (mileage) takes @Quantity and prices it; any other takes @Amount.
-- Receipt reading: pass what Pilo read (@ReceiptGenerationId from ai.usp_Generation_Log with Feature RECEIPT,
-- @ReceiptReadJson, @ReceiptConfidence); the receipt photo itself is an ap.BillAttachment row with this BillLineId.
CREATE PROCEDURE ap.usp_Expense_Save
    @BillLineId             INT = NULL OUTPUT,
    @ExpenseDate            DATE = NULL,
    @ExpenseCategoryId      INT = NULL,
    @Description            NVARCHAR(500) = NULL,
    @Amount                 DECIMAL(19,2) = NULL,
    @Quantity               DECIMAL(19,4) = NULL,
    @ProjectId              INT = NULL,
    @TaskId                 INT = NULL,
    @IsBillable             BIT = 0,
    @Merchant               NVARCHAR(200) = NULL,
    @ReceiptGenerationId    BIGINT = NULL,
    @ReceiptReadJson        NVARCHAR(MAX) = NULL,
    @ReceiptConfidence      DECIMAL(5,4) = NULL,
    @ForUserId              INT = NULL,
    @Delete                 BIT = 0,
    @BillId                 INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TenantId INT = CONVERT(INT, SESSION_CONTEXT(N'TenantId')),
            @UserId   INT = CONVERT(INT, SESSION_CONTEXT(N'UserId')),
            @Now DATETIME2(0) = SYSUTCDATETIME(),
            @OwnerId INT, @OldBillId INT, @OldTimesheetId INT, @TimesheetId INT, @WeekEnd DATE, @ReportDesc NVARCHAR(500),
            @Status VARCHAR(30), @UnitRate DECIMAL(19,4), @UnitPrice DECIMAL(19,4), @BillNumber NVARCHAR(50);

    IF @TenantId IS NULL OR @UserId IS NULL THROW 52301, N'SESSION_CONTEXT TenantId and UserId must be set.', 1;

    IF @BillLineId IS NOT NULL
    BEGIN
        SELECT @OldBillId = b.Id, @OwnerId = b.PayeeUserId, @OldTimesheetId = b.TimesheetId
        FROM ap.BillLine AS l JOIN ap.Bill AS b ON b.TenantId = l.TenantId AND b.Id = l.BillId
        WHERE l.TenantId = @TenantId AND l.Id = @BillLineId;
        IF @OldTimesheetId IS NULL THROW 52302, N'Unknown expense.', 1;
    END
    ELSE SET @OwnerId = ISNULL(@ForUserId, @UserId);

    IF @OwnerId <> @UserId AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'time.enter_others'))
        THROW 52303, N'You can only enter your own expenses.', 1;
    IF @OwnerId = @UserId AND NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'expense.submit'))
        THROW 52304, N'You need permission to submit expenses.', 1;

    IF @Delete = 0
    BEGIN
        IF @ExpenseDate IS NULL OR @ExpenseCategoryId IS NULL OR NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL
            THROW 52305, N'An expense needs a date, a category and a description.', 1;
        SELECT @UnitRate = UnitRate FROM lkp.ExpenseCategory WHERE TenantId = @TenantId AND Id = @ExpenseCategoryId AND IsActive = 1;
        IF @@ROWCOUNT = 0 THROW 52306, N'Unknown expense category.', 1;
        IF @UnitRate IS NOT NULL
        BEGIN
            IF @Quantity IS NULL OR @Quantity <= 0 THROW 52307, N'Enter the quantity (for example, miles) for this category.', 1;
            SELECT @UnitPrice = @UnitRate, @Amount = ROUND(@Quantity * @UnitRate, 2);
        END
        ELSE
        BEGIN
            IF @Amount IS NULL OR @Amount <= 0 THROW 52307, N'The amount must be more than zero.', 1;
            SELECT @Quantity = 1, @UnitPrice = @Amount;
        END;
        IF @IsBillable = 1 AND @ProjectId IS NULL THROW 52308, N'A billable expense needs a project.', 1;
        IF @ReceiptReadJson IS NOT NULL AND ISJSON(@ReceiptReadJson) = 0 THROW 52309, N'The receipt reading must be JSON.', 1;
        IF @ReceiptGenerationId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM ai.Generation WHERE TenantId = @TenantId AND Id = @ReceiptGenerationId AND Feature = 'RECEIPT')
            THROW 52309, N'The receipt reading isn''t a logged Pilo receipt read.', 1;
    END;

    BEGIN TRAN;

    -- the report the line is on now must still be a draft
    IF @OldBillId IS NOT NULL
    BEGIN
        SELECT @Status = s.SystemCode FROM ap.Bill AS b WITH (UPDLOCK)
        JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
        WHERE b.TenantId = @TenantId AND b.Id = @OldBillId;
        IF @Status <> 'DRAFT' THROW 52310, N'This week''s expenses are already submitted. They can change once the week is sent back.', 1;
    END;

    IF @Delete = 1
    BEGIN
        IF @OldBillId IS NULL THROW 52302, N'Unknown expense.', 1;
        UPDATE ap.BillAttachment SET BillLineId = NULL, DeletedAt = ISNULL(DeletedAt, @Now)
        WHERE TenantId = @TenantId AND BillLineId = @BillLineId;
        DELETE FROM ap.BillLine WHERE TenantId = @TenantId AND Id = @BillLineId;
        EXEC ap.usp_Bill_Recalculate @BillId = @OldBillId;
        EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @OldTimesheetId;
        SELECT @BillId = @OldBillId, @BillLineId = NULL;
        COMMIT;
        RETURN;
    END;

    -- the week's timesheet and expense report
    EXEC crm.usp_Timesheet_Ensure @TenantId = @TenantId, @AppUserId = @OwnerId, @WorkDate = @ExpenseDate, @TimesheetId = @TimesheetId OUTPUT;

    SET @BillId = NULL;
    SELECT @BillId = b.Id, @Status = s.SystemCode
    FROM ap.Bill AS b WITH (UPDLOCK, HOLDLOCK)
    JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
    WHERE b.TenantId = @TenantId AND b.TimesheetId = @TimesheetId AND b.VoidedAt IS NULL;

    IF @BillId IS NULL
    BEGIN
        SELECT @WeekEnd = WeekEnd, @ReportDesc = CONCAT(N'Expenses for the week of ', FORMAT(WeekStart, 'MMM d, yyyy', 'en-US'))
        FROM crm.Timesheet WHERE TenantId = @TenantId AND Id = @TimesheetId;
        EXEC ap.usp_Bill_Create @PayeeUserId = @OwnerId, @BillDate = @WeekEnd, @Description = @ReportDesc,
             @BillId = @BillId OUTPUT, @BillNumber = @BillNumber OUTPUT;
        UPDATE ap.Bill SET TimesheetId = @TimesheetId WHERE TenantId = @TenantId AND Id = @BillId;
        SET @Status = 'DRAFT';
    END;

    IF @Status <> 'DRAFT' THROW 52310, N'This week''s expenses are already submitted. They can change once the week is sent back.', 1;

    IF @BillLineId IS NULL
    BEGIN
        INSERT INTO ap.BillLine (TenantId, BillId, LineNumber, ExpenseDate, ExpenseCategoryId, Description, Quantity, UnitPrice, Amount,
                                 ProjectId, TaskId, IsBillable, Merchant, ReceiptGenerationId, ReceiptReadJson, ReceiptConfidence)
        SELECT @TenantId, @BillId, ISNULL(MAX(l.LineNumber), 0) + 1, @ExpenseDate, @ExpenseCategoryId, @Description, @Quantity, @UnitPrice, @Amount,
               @ProjectId, @TaskId, @IsBillable, @Merchant, @ReceiptGenerationId, @ReceiptReadJson, @ReceiptConfidence
        FROM ap.BillLine AS l WHERE l.TenantId = @TenantId AND l.BillId = @BillId;
        SET @BillLineId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE l
        SET BillId = @BillId,
            LineNumber = IIF(@BillId = @OldBillId, l.LineNumber,
                             (SELECT ISNULL(MAX(x.LineNumber), 0) + 1 FROM ap.BillLine AS x WHERE x.TenantId = @TenantId AND x.BillId = @BillId)),
            ExpenseDate = @ExpenseDate, ExpenseCategoryId = @ExpenseCategoryId, Description = @Description,
            Quantity = @Quantity, UnitPrice = @UnitPrice, Amount = @Amount, ProjectId = @ProjectId, TaskId = @TaskId,
            IsBillable = @IsBillable, Merchant = @Merchant,
            ReceiptGenerationId = COALESCE(@ReceiptGenerationId, l.ReceiptGenerationId),
            ReceiptReadJson = COALESCE(@ReceiptReadJson, l.ReceiptReadJson),
            ReceiptConfidence = COALESCE(@ReceiptConfidence, l.ReceiptConfidence),
            ModifiedAt = @Now, ModifiedBy = @UserId
        FROM ap.BillLine AS l
        WHERE l.TenantId = @TenantId AND l.Id = @BillLineId;

        IF @BillId <> @OldBillId
        BEGIN
            -- the receipt moves with its line
            UPDATE ap.BillAttachment SET BillId = @BillId WHERE TenantId = @TenantId AND BillLineId = @BillLineId;
            EXEC ap.usp_Bill_Recalculate @BillId = @OldBillId;
            EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @OldTimesheetId;
        END;
    END;

    EXEC ap.usp_Bill_Recalculate @BillId = @BillId;
    EXEC crm.usp_Timesheet_SyncStatus @TenantId = @TenantId, @TimesheetId = @TimesheetId;

    COMMIT;
END;
