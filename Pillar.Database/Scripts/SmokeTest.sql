/*
Smoke test: run against a freshly published Pillar database (SQL Server 2019+), in SSMS or sqlcmd.
Walks one tenant through the billing path end to end:
  tenant sign-up -> client (default billing profile) -> contact (billing contact) -> project, user, rate
  -> task -> time entry (save, submit, auto-approve) -> invoice run -> issue (number, fee) -> rendering data -> payments (partial, paid, voided) -> invoice void (fee reversal)
  -> vendor bill (auto-approve, pay) -> billable expense rebilled on the next run -> draft deleted
  -> Pillar monthly statement (generate, minimum, card charge failed then paid)
  -> no-login subcontractor with owner-entered time, invited to log in, sign-in lockout
  -> fixed-fee milestones -> MFA recovery code -> weekly timesheet approval, plan features, UI preferences, recent items.
Every step asserts its result and THROWs on the first failure. Everything runs in one transaction that is
rolled back at the end, so the database is left as it was. Set @Keep = 1 to commit and inspect the rows.
Not part of the build (Scripts\** is excluded) and not run on publish.
*/
SET QUOTED_IDENTIFIER ON;   -- filtered indexes need it; older sqlcmd (ODBC 17) turns it off unless run with -I
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Keep BIT = 0;
DECLARE @UserId INT;                           -- the owner created by sign-up
DECLARE @OwnerEmail NVARCHAR(254) = CONCAT(N'owner+', NEWID(), N'@smoke.test');
DECLARE @WorkDate DATE = DATEADD(DAY, -1, CAST(SYSUTCDATETIME() AS DATE));
DECLARE @Rate DECIMAL(19,4) = 150;

DECLARE @TenantId INT, @ClientId INT, @ProfileId INT, @ContactId INT, @ProjectId INT,
        @TaskId INT, @TaskKey VARCHAR(20), @TimeEntryId INT, @RunId INT, @InvoiceId INT,
        @Msg NVARCHAR(400);

BEGIN TRAN;

------------------------------------------------------------------ 1. Tenant sign-up
EXEC admin.usp_Tenant_SignUp @TenantName = N'Smoke Test Tenant', @OwnerEmail = @OwnerEmail, @OwnerFirstName = N'Smoke',
     @OwnerLastName = N'Owner', @PasswordHash = '$2b$12$smoke.test.hash.not.a.real.bcrypt.value.........',
     @TenantTypeCode = 'CONTRACTOR', @TenantId = @TenantId OUTPUT, @AppUserId = @UserId OUTPUT;
IF @TenantId IS NULL OR @UserId IS NULL THROW 59001, N'Sign-up did not create the tenant and owner. Are the post-deploy seeds in place?', 1;
EXEC sp_set_session_context N'UserId', @UserId;    -- sign-up already set TenantId

IF NOT EXISTS (SELECT 1 FROM sec.AppUser AS u JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId
               WHERE u.Id = @UserId AND r.Code = 'OWNER' AND u.Status = 'ACTIVE')
   OR (SELECT COUNT(*) FROM sec.Role WHERE TenantId = @TenantId) <> 5
   OR NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
    THROW 59037, N'Sign-up should create five roles and an active owner holding every permission.', 1;

IF NOT EXISTS (SELECT 1 FROM lkp.ClientStatus WHERE TenantId = @TenantId AND SystemCode = 'ACTIVE')
    THROW 59002, N'Lookup sync did not copy ClientStatus to the tenant.', 1;
IF NOT EXISTS (SELECT 1 FROM ar.InvoiceLayout WHERE TenantId = @TenantId AND Code = N'SUMMARY' AND IsDefault = 1)
    THROW 59028, N'Invoice layouts were not seeded (is admin.Report seeded?).', 1;
PRINT 'ok 1  signed up: tenant, owner, roles, lookups, settings and invoice layouts';

------------------------------------------------------------------ 2. Client gets a default billing profile
INSERT INTO crm.Client (TenantId, ClientCode, Name, ClientTypeId, ClientStatusId)
SELECT @TenantId, N'SMOKE', N'Smoke Test Client', ct.Id, cs.Id
FROM lkp.ClientType AS ct
JOIN lkp.ClientStatus AS cs ON cs.TenantId = ct.TenantId AND cs.SystemCode = 'ACTIVE'
WHERE ct.TenantId = @TenantId AND ct.SystemCode = 'BUSINESS';
SET @ClientId = SCOPE_IDENTITY();

SELECT @ProfileId = Id FROM crm.ClientBillingProfile WHERE TenantId = @TenantId AND ClientId = @ClientId AND IsDefault = 1;
IF @ProfileId IS NULL THROW 59003, N'trg_Client_CreateDefaultBillingProfile did not create a default profile.', 1;
PRINT 'ok 2  client created with default billing profile';

------------------------------------------------------------------ 3. First contact becomes the billing contact
INSERT INTO crm.Contact (TenantId, ClientId, FirstName, LastName, Email, IsPrimary)
VALUES (@TenantId, @ClientId, N'Pat', N'Payer', N'pat@example.com', 1);
SET @ContactId = SCOPE_IDENTITY();

IF NOT EXISTS (SELECT 1 FROM crm.ClientBillingProfile WHERE Id = @ProfileId AND BillingContactId = @ContactId)
    THROW 59004, N'trg_Contact_FillBillingContact did not fill the profile''s billing contact.', 1;
PRINT 'ok 3  contact filled the billing contact';

------------------------------------------------------------------ 4. Hourly project, project user, rate
INSERT INTO crm.ClientProject (TenantId, ClientId, BillingProfileId, ProjectCode, Name, ProjectTypeId, BillingTypeId, ProjectStatusId)
SELECT @TenantId, @ClientId, @ProfileId, N'SMOKE-1', N'Smoke Test Project', pt.Id, bt.Id, ps.Id
FROM lkp.ProjectType AS pt
JOIN lkp.BillingType AS bt ON bt.TenantId = pt.TenantId AND bt.SystemCode = 'HOURLY'
JOIN lkp.ProjectStatus AS ps ON ps.TenantId = pt.TenantId AND ps.SystemCode = 'OPEN'
WHERE pt.TenantId = @TenantId AND pt.Code = N'PM';
SET @ProjectId = SCOPE_IDENTITY();
IF @ProjectId IS NULL THROW 59005, N'Project not created.', 1;

INSERT INTO crm.ProjectUser (TenantId, ProjectId, AppUserId) VALUES (@TenantId, @ProjectId, @UserId);
INSERT INTO crm.ProjectRate (TenantId, ProjectId, AppUserId, Rate, EffectiveFrom)
VALUES (@TenantId, @ProjectId, @UserId, @Rate, DATEADD(MONTH, -1, @WorkDate));
PRINT 'ok 4  project, project user and rate created';

------------------------------------------------------------------ 5. Task through the create proc
EXEC crm.usp_ClientTask_Create @ProjectId = @ProjectId, @Title = N'Smoke test task',
     @TaskId = @TaskId OUTPUT, @TaskKey = @TaskKey OUTPUT;
IF @TaskId IS NULL OR @TaskKey NOT LIKE 'PM-%' THROW 59006, N'usp_ClientTask_Create did not return a PM- task key.', 1;
PRINT CONCAT('ok 5  task created: ', @TaskKey);

------------------------------------------------------------------ 6. Time: save 90 minutes, submit (contractor auto-approves)
EXEC crm.usp_TimeEntry_Save @TimeEntryId = @TimeEntryId OUTPUT, @TaskId = @TaskId, @WorkDate = @WorkDate,
     @Minutes = 90, @Description = N'Smoke test work';
EXEC crm.usp_TimeEntry_Submit @TimeEntryId = @TimeEntryId;

IF NOT EXISTS (
    SELECT 1 FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    WHERE e.Id = @TimeEntryId AND s.SystemCode = 'APPROVED' AND e.RateApplied = @Rate AND e.AmountBillable = 225.00)
    THROW 59007, N'Time entry is not APPROVED at the user rate with AmountBillable 225.00.', 1;
PRINT 'ok 6  time entry approved: 1.5 h x 150 = 225.00';

------------------------------------------------------------------ 7. Invoice run builds one draft
EXEC ar.usp_InvoiceRun_Generate @PeriodEnd = @WorkDate, @ClientId = @ClientId, @InvoiceRunId = @RunId OUTPUT;

SELECT @InvoiceId = i.Id FROM ar.Invoice AS i
JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
WHERE i.TenantId = @TenantId AND i.InvoiceRunId = @RunId AND s.SystemCode = 'DRAFT';
IF @InvoiceId IS NULL THROW 59008, N'Invoice run did not create a draft invoice.', 1;
IF NOT EXISTS (SELECT 1 FROM ar.Invoice WHERE Id = @InvoiceId AND SubTotal = 225.00 AND InvoiceNumber IS NULL)
    THROW 59009, N'Draft invoice should be unnumbered with SubTotal 225.00.', 1;
IF NOT EXISTS (SELECT 1 FROM crm.TimeEntry WHERE Id = @TimeEntryId AND InvoiceEntryId IS NOT NULL)
    THROW 59010, N'Time entry was not linked to an invoice line.', 1;
PRINT 'ok 7  invoice run created a 225.00 draft';

------------------------------------------------------------------ 8. Issue: number, due date, time INVOICED, fee accrued
EXEC ar.usp_Invoice_Issue @InvoiceId = @InvoiceId;

IF NOT EXISTS (
    SELECT 1 FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.Id = @InvoiceId AND s.SystemCode = 'ISSUED' AND i.InvoiceNumber IS NOT NULL AND i.DueDate IS NOT NULL
      AND i.BillToContactId = @ContactId)
    THROW 59011, N'Issued invoice is missing status, number, due date or bill-to snapshot.', 1;
IF NOT EXISTS (
    SELECT 1 FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    WHERE e.Id = @TimeEntryId AND s.SystemCode = 'INVOICED')
    THROW 59012, N'Time entry is not INVOICED after issue.', 1;
IF NOT EXISTS (
    SELECT 1 FROM admin.PlatformFee
    WHERE TenantId = @TenantId AND InvoiceId = @InvoiceId AND FeeStatus = 'ACCRUED'
      AND FeeBaseAmount = 225.00 AND FeeRate = 0.025 AND ABS(FeeAmount - 5.63) <= 0.01)
    THROW 59013, N'Platform fee was not accrued at 2.5% of 225.00.', 1;
SELECT @Msg = CONCAT('ok 8  issued ', InvoiceNumber, ', due ', DueDate) FROM ar.Invoice WHERE Id = @InvoiceId;
PRINT @Msg;

------------------------------------------------------------------ 8b. Rendering: logo upload, layout snapshot, invoice detail rows
DECLARE @Png VARBINARY(MAX) = 0x89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000D4944415478DA63F8FFFF3F0005FE02FEA7D6A5A40000000049454E44AE426082;  -- 1x1 PNG
EXEC admin.usp_TenantBranding_SetLogo @LogoImage = @Png, @LogoFileName = N'logo.png';
IF NOT EXISTS (SELECT 1 FROM admin.TenantBranding WHERE TenantId = @TenantId AND LogoMimeType = 'image/png' AND LogoBytes = DATALENGTH(@Png))
    THROW 59029, N'Logo was not saved as image/png.', 1;
IF NOT EXISTS (
    SELECT 1 FROM ar.Invoice AS i
    JOIN ar.InvoiceLayout AS l ON l.TenantId = i.TenantId AND l.Id = i.InvoiceLayoutId
    WHERE i.Id = @InvoiceId AND l.Code = N'SUMMARY')
    THROW 59030, N'Issue did not snapshot the tenant default layout.', 1;
IF NOT EXISTS (
    SELECT 1 FROM ar.vw_InvoiceDetail
    WHERE InvoiceId = @InvoiceId AND TimeEntryId = @TimeEntryId AND ReportCode = 'INVOICE_S'
      AND Total = 225.00 AND LineAmountOnce = 225.00 AND CompanyName = N'Smoke Test Tenant' AND BillToName IS NOT NULL)
    THROW 59031, N'ar.vw_InvoiceDetail is missing the issued line, its time entry or the header.', 1;
PRINT 'ok 8b logo saved, default layout snapshotted, invoice detail returns header, line and time';

------------------------------------------------------------------ 9. Payments: partial, then paid, then a bounced payment voided
DECLARE @Pay1 INT, @Pay2 INT;
INSERT INTO ar.InvoicePay (TenantId, ClientId, PaymentDate, Amount, PaymentMethodId, ReferenceNumber)
SELECT @TenantId, @ClientId, @WorkDate, 100.00, Id, N'CHK-1' FROM lkp.PaymentMethod WHERE TenantId = @TenantId AND IsDefault = 1;
SET @Pay1 = SCOPE_IDENTITY();
EXEC ar.usp_InvoicePay_Apply @InvoiceId = @InvoiceId, @InvoicePayId = @Pay1;
IF NOT EXISTS (
    SELECT 1 FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.Id = @InvoiceId AND s.SystemCode = 'PARTIAL' AND i.AmountPaid = 100.00 AND i.BalanceDue = 125.00)
    THROW 59016, N'A 100.00 payment should leave the invoice PARTIAL with 125.00 due.', 1;

INSERT INTO ar.InvoicePay (TenantId, ClientId, PaymentDate, Amount, PaymentMethodId, ReferenceNumber)
SELECT @TenantId, @ClientId, @WorkDate, 200.00, Id, N'CHK-2' FROM lkp.PaymentMethod WHERE TenantId = @TenantId AND IsDefault = 1;
SET @Pay2 = SCOPE_IDENTITY();
EXEC ar.usp_InvoicePay_Apply @InvoiceId = @InvoiceId, @InvoicePayId = @Pay2;   -- NULL amount: applies only the 125.00 due
IF NOT EXISTS (
    SELECT 1 FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.Id = @InvoiceId AND s.SystemCode = 'PAID' AND i.BalanceDue = 0)
    THROW 59017, N'Second payment should leave the invoice PAID.', 1;
IF NOT EXISTS (SELECT 1 FROM ar.InvoicePay WHERE Id = @Pay2 AND AmountApplied = 125.00 AND UnappliedAmount = 75.00)
    THROW 59018, N'Second payment should apply 125.00 and leave 75.00 unapplied.', 1;

EXEC ar.usp_InvoicePay_Void @InvoicePayId = @Pay1, @Reason = N'Smoke test bounced check';
EXEC ar.usp_InvoicePay_Void @InvoicePayId = @Pay2, @Reason = N'Smoke test';
IF NOT EXISTS (
    SELECT 1 FROM ar.Invoice AS i
    JOIN lkp.InvoiceStatus AS s ON s.TenantId = i.TenantId AND s.Id = i.InvoiceStatusId
    WHERE i.Id = @InvoiceId AND s.SystemCode = 'ISSUED' AND i.AmountPaid = 0)
    THROW 59019, N'Voiding both payments should return the invoice to ISSUED with nothing paid.', 1;
PRINT 'ok 9  payments applied (PARTIAL, PAID) and voided (back to ISSUED)';

------------------------------------------------------------------ 10. Void invoice: fee reversed, time released
EXEC ar.usp_Invoice_Void @InvoiceId = @InvoiceId, @Reason = N'Smoke test';

IF (SELECT SUM(FeeAmount) FROM admin.PlatformFee WHERE TenantId = @TenantId AND InvoiceId = @InvoiceId) <> 0
    THROW 59014, N'Void did not reverse the platform fee to a net of zero.', 1;
IF NOT EXISTS (
    SELECT 1 FROM crm.TimeEntry AS e
    JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
    WHERE e.Id = @TimeEntryId AND s.SystemCode = 'APPROVED')
    THROW 59015, N'Void did not release the time entry back to APPROVED.', 1;
PRINT 'ok 10 void reversed the fee and released the time';

------------------------------------------------------------------ 11. AP: vendor bill with a billable mileage line, auto-approved, paid
DECLARE @VendorId INT, @BillId INT, @BillNumber NVARCHAR(50), @BillLineId INT, @BillPayId INT, @RunId2 INT, @InvoiceId2 INT;
INSERT INTO ap.Vendor (TenantId, VendorCode, Name) VALUES (@TenantId, N'SMOKEV', N'Smoke Test Vendor');
SET @VendorId = SCOPE_IDENTITY();

EXEC ap.usp_Bill_Create @VendorId = @VendorId, @BillDate = @WorkDate, @VendorInvoiceNumber = N'V-1001',
     @BillId = @BillId OUTPUT, @BillNumber = @BillNumber OUTPUT;
IF @BillId IS NULL OR @BillNumber IS NULL THROW 59020, N'usp_Bill_Create did not return a numbered bill.', 1;

INSERT INTO ap.BillLine (TenantId, BillId, LineNumber, ExpenseDate, ExpenseCategoryId, Description, Quantity, UnitPrice, Amount,
                         ProjectId, IsBillable, MarkupPercent)
SELECT @TenantId, @BillId, 1, @WorkDate, Id, N'Smoke test site visit', 100, 0.70, 70.00, @ProjectId, 1, 0.10
FROM lkp.ExpenseCategory WHERE TenantId = @TenantId AND Code = N'MILEAGE';
SET @BillLineId = SCOPE_IDENTITY();
IF @BillLineId IS NULL THROW 59021, N'No MILEAGE expense category for the tenant.', 1;

EXEC ap.usp_Bill_Submit @BillId = @BillId;   -- contractor: AP.RequireApproval is off, so this goes straight to OPEN
IF NOT EXISTS (
    SELECT 1 FROM ap.Bill AS b JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
    WHERE b.Id = @BillId AND s.SystemCode = 'OPEN' AND b.Total = 70.00)
    THROW 59022, N'Submitted bill should be OPEN with Total 70.00.', 1;

INSERT INTO ap.BillPay (TenantId, VendorId, PaymentDate, Amount, PaymentMethodId, ReferenceNumber)
SELECT @TenantId, @VendorId, @WorkDate, 70.00, Id, N'OUT-1' FROM lkp.PaymentMethod WHERE TenantId = @TenantId AND IsDefault = 1;
SET @BillPayId = SCOPE_IDENTITY();
EXEC ap.usp_BillPay_Apply @BillPayId = @BillPayId, @BillId = @BillId;
IF NOT EXISTS (
    SELECT 1 FROM ap.Bill AS b JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
    WHERE b.Id = @BillId AND s.SystemCode = 'PAID' AND b.BalanceDue = 0)
    THROW 59023, N'Bill should be PAID after a 70.00 payment.', 1;
PRINT CONCAT('ok 11 vendor bill ', @BillNumber, ' opened and paid');

------------------------------------------------------------------ 12. Rebill: next invoice run picks up the time and the expense with markup
EXEC ar.usp_InvoiceRun_Generate @PeriodEnd = @WorkDate, @ClientId = @ClientId, @InvoiceRunId = @RunId2 OUTPUT;
SELECT @InvoiceId2 = Id FROM ar.Invoice WHERE TenantId = @TenantId AND InvoiceRunId = @RunId2;
IF @InvoiceId2 IS NULL THROW 59024, N'Second invoice run did not create a draft.', 1;
IF NOT EXISTS (SELECT 1 FROM ar.Invoice WHERE Id = @InvoiceId2 AND SubTotal = 302.00)
    THROW 59025, N'Draft should be 225.00 time + 77.00 expense (70.00 + 10% markup) = 302.00.', 1;
IF NOT EXISTS (
    SELECT 1 FROM ap.BillLine AS bl
    JOIN ar.InvoiceEntry AS ie ON ie.TenantId = bl.TenantId AND ie.Id = bl.InvoiceEntryId
    JOIN lkp.InvoiceLineType AS lt ON lt.TenantId = ie.TenantId AND lt.Id = ie.LineTypeId
    WHERE bl.Id = @BillLineId AND ie.InvoiceId = @InvoiceId2 AND lt.SystemCode = 'EXPENSE')
    THROW 59026, N'Bill line is not linked to an EXPENSE line on the draft.', 1;

EXEC ar.usp_Invoice_DeleteDraft @InvoiceRunId = @RunId2;
IF EXISTS (SELECT 1 FROM ap.BillLine WHERE Id = @BillLineId AND InvoiceEntryId IS NOT NULL)
    OR EXISTS (SELECT 1 FROM crm.TimeEntry WHERE Id = @TimeEntryId AND InvoiceEntryId IS NOT NULL)
    THROW 59027, N'Deleting the draft did not release the bill line and time entry.', 1;
PRINT 'ok 12 expense rebilled at 77.00 on a 302.00 draft; deleting the draft released it';

------------------------------------------------------------------ 13. Pillar statement: month-end generate, minimum, card charge (fail, then succeed)
DECLARE @ThisMonth DATE = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1), @StatementId INT, @CardId INT;
EXEC sp_set_session_context N'IsPlatformAdmin', 1;

EXEC admin.usp_PlatformStatement_Generate @PeriodStart = @ThisMonth, @TenantId = @TenantId;
SELECT @StatementId = Id FROM admin.PlatformStatement WHERE TenantId = @TenantId AND PeriodStart = @ThisMonth AND Status <> 'VOID';
IF @StatementId IS NULL
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WHERE Id = @StatementId AND FeeTotal = 0 AND AmountDue = 0 AND Status = 'PAID')
   OR (SELECT COUNT(*) FROM admin.PlatformStatementLine WHERE StatementId = @StatementId AND LineType IN ('FEE', 'REVERSAL')) <> 2
   OR EXISTS (SELECT 1 FROM admin.PlatformFee WHERE TenantId = @TenantId AND PlatformStatementId IS NULL)
    THROW 59032, N'Statement should bill the fee and its reversal (net 0.00, PAID) and leave no fee unbilled.', 1;
EXEC admin.usp_PlatformStatement_Generate @PeriodStart = @ThisMonth, @TenantId = @TenantId;   -- rerun: no second statement
IF (SELECT COUNT(*) FROM admin.PlatformStatement WHERE TenantId = @TenantId AND Status <> 'VOID') <> 1
    THROW 59033, N'Rerunning the month created a second statement.', 1;

-- treat the tenant as an established one with a 25.00 minimum, then regenerate the month
EXEC admin.usp_PlatformStatement_Void @StatementId = @StatementId, @Reason = N'Smoke test: minimum';
UPDATE admin.Tenant SET CreatedAt = DATEADD(MONTH, -2, CreatedAt) WHERE Id = @TenantId;
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Platform.MonthlyMinimumOverride', @Value = N'25';
EXEC admin.usp_PlatformStatement_Generate @PeriodStart = @ThisMonth, @TenantId = @TenantId;
SELECT @StatementId = Id FROM admin.PlatformStatement WHERE TenantId = @TenantId AND PeriodStart = @ThisMonth AND Status <> 'VOID';
IF NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WHERE Id = @StatementId AND MinimumAdjustment = 25.00 AND AmountDue = 25.00 AND Status = 'OPEN')
    THROW 59034, N'Regenerated statement should be OPEN for the 25.00 monthly minimum.', 1;

INSERT INTO admin.TenantPaymentMethod (TenantId, ProcessorCustomerId, ProcessorPaymentMethodId, MethodType, Brand, Last4, ExpMonth, ExpYear, IsDefault)
VALUES (@TenantId, 'cus_smoke', 'pm_smoke', 'CARD', N'Visa', '4242', 12, 2030, 1);
SET @CardId = SCOPE_IDENTITY();
EXEC admin.usp_PlatformStatement_RecordPayment @StatementId = @StatementId, @Amount = 25.00, @Succeeded = 0,
     @PaymentMethodId = @CardId, @FailureReason = N'card_declined';
IF NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WHERE Id = @StatementId AND Status = 'PAST_DUE' AND FailedAttempts = 1)
    THROW 59035, N'A failed charge should mark the statement PAST_DUE.', 1;
EXEC admin.usp_PlatformStatement_RecordPayment @StatementId = @StatementId, @Amount = 25.00, @Succeeded = 1,
     @PaymentMethodId = @CardId, @ProcessorChargeId = 'pi_smoke';
EXEC admin.usp_PlatformStatement_RecordPayment @StatementId = @StatementId, @Amount = 25.00, @Succeeded = 1,
     @PaymentMethodId = @CardId, @ProcessorChargeId = 'pi_smoke';   -- repeated webhook: ignored
IF NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WHERE Id = @StatementId AND Status = 'PAID' AND AmountPaid = 25.00 AND BalanceDue = 0)
   OR (SELECT COUNT(*) FROM admin.PlatformPayment WHERE StatementId = @StatementId) <> 2
   OR EXISTS (SELECT 1 FROM admin.PlatformFee WHERE TenantId = @TenantId AND FeeStatus IN ('ACCRUED', 'BILLED'))
    THROW 59036, N'Successful charge should mark the statement and its fees PAID exactly once.', 1;

EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
PRINT 'ok 13 Pillar statement generated (net 0.00), regenerated with a 25.00 minimum, charge failed then paid';

------------------------------------------------------------------ 14. People: no-login subcontractor, on-behalf time, invite, sign-in
DECLARE @SubId INT, @SubEntryId INT, @Invite BINARY(32) = HASHBYTES('SHA2_256', CONCAT('invite', NEWID())),
        @SubEmail NVARCHAR(254) = CONCAT(N'sub+', NEWID(), N'@smoke.test'), @i INT = 0;

INSERT INTO sec.AppUser (TenantId, FirstName, LastName, UserType, RoleId, CanLogin)
SELECT @TenantId, N'Sam', N'Subcontractor', 'CONTRACTOR', r.Id, 0 FROM sec.Role AS r WHERE r.TenantId = @TenantId AND r.Code = 'MEMBER';
SET @SubId = SCOPE_IDENTITY();
INSERT INTO crm.ProjectUser (TenantId, ProjectId, AppUserId) VALUES (@TenantId, @ProjectId, @SubId);

EXEC crm.usp_TimeEntry_Save @TimeEntryId = @SubEntryId OUTPUT, @TaskId = @TaskId, @WorkDate = @WorkDate,
     @Minutes = 60, @Description = N'Entered by the owner', @ForUserId = @SubId;
EXEC crm.usp_TimeEntry_Submit @TimeEntryId = @SubEntryId;
IF NOT EXISTS (SELECT 1 FROM crm.TimeEntry WHERE Id = @SubEntryId AND AppUserId = @SubId AND CreatedBy = @UserId)
    THROW 59038, N'Owner could not enter time for the no-login subcontractor.', 1;

EXEC sec.usp_User_Invite @Email = @SubEmail, @TokenHash = @Invite, @AppUserId = @SubId OUTPUT;
IF NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE Id = @SubId AND CanLogin = 1 AND Status = 'INVITED')
   OR NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @SubId AND PasswordHash IS NULL)
    THROW 59039, N'Invite should give the same row a pending login.', 1;

CREATE TABLE #Redeemed (AppUserId INT, TenantId INT);
INSERT INTO #Redeemed EXEC sec.usp_Auth_RedeemToken @TokenHash = @Invite, @Purpose = 'INVITE', @PasswordHash = '$2b$12$smoke.sub.hash';
IF NOT EXISTS (SELECT 1 FROM #Redeemed WHERE AppUserId = @SubId)
   OR NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE Id = @SubId AND Status = 'ACTIVE')
   OR NOT EXISTS (SELECT 1 FROM crm.TimeEntry WHERE Id = @SubEntryId AND AppUserId = @SubId)
    THROW 59040, N'Accepting the invite should activate the user and keep their time.', 1;
INSERT INTO #Redeemed EXEC sec.usp_Auth_RedeemToken @TokenHash = @Invite, @Purpose = 'INVITE', @PasswordHash = 'again';
IF (SELECT COUNT(*) FROM #Redeemed) <> 1 THROW 59041, N'An invite link worked twice.', 1;

WHILE @i < 5
BEGIN
    EXEC sec.usp_Auth_RecordLogin @EventType = 'LOGIN_FAIL', @Email = @SubEmail;
    SET @i += 1;
END;
IF NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @SubId AND LockedUntil > SYSUTCDATETIME())
    THROW 59042, N'Five failed sign-ins should lock the login.', 1;
DROP TABLE #Redeemed;
PRINT 'ok 14 no-login subcontractor got owner-entered time, then an invite; sign-in lockout works';

------------------------------------------------------------------ 15. Fixed fee: milestone schedule (date, task, manual) billed as each is ready
DECLARE @FfProjectId INT, @FfTaskId INT, @FfTaskKey VARCHAR(20), @FfRunId INT, @FfRunId2 INT, @FfInvoiceId INT,
        @DateMsId INT, @ManualMsId INT, @Today DATE = CAST(SYSUTCDATETIME() AS DATE), @Schedule NVARCHAR(MAX);

INSERT INTO crm.ClientProject (TenantId, ClientId, BillingProfileId, ProjectCode, Name, ProjectTypeId, BillingTypeId, ProjectStatusId, FixedFeeAmount)
SELECT @TenantId, @ClientId, @ProfileId, N'SMOKE-FF', N'Smoke Fixed Fee Project', pt.Id, bt.Id, ps.Id, 10000
FROM lkp.ProjectType AS pt
JOIN lkp.BillingType AS bt ON bt.TenantId = pt.TenantId AND bt.SystemCode = 'FIXED'
JOIN lkp.ProjectStatus AS ps ON ps.TenantId = pt.TenantId AND ps.SystemCode = 'OPEN'
WHERE pt.TenantId = @TenantId AND pt.Code = N'PM';
SET @FfProjectId = SCOPE_IDENTITY();
EXEC crm.usp_ClientTask_Create @ProjectId = @FfProjectId, @Title = N'Design sign-off',
     @TaskId = @FfTaskId OUTPUT, @TaskKey = @FfTaskKey OUTPUT;

-- 25% on a date already passed, 4,000.00 when the task is done, and the remaining 35% on manual sign-off
SET @Schedule = CONCAT(N'[{"name":"Kickoff","percent":0.25,"trigger":"DATE","billDate":"', CONVERT(CHAR(10), @WorkDate, 23), N'"},',
                       N'{"name":"Design","amount":4000,"trigger":"TASK","taskId":', @FfTaskId, N'},',
                       N'{"name":"Go-live","percent":0.35,"trigger":"MANUAL"}]');
EXEC crm.usp_ProjectMilestone_Save @ProjectId = @FfProjectId, @Milestones = @Schedule;
IF (SELECT COUNT(*) FROM crm.ProjectBillingMilestone WHERE ProjectId = @FfProjectId) <> 3
   OR (SELECT SUM(Amount) FROM crm.ProjectBillingMilestone WHERE ProjectId = @FfProjectId) <> 10000.00
   OR NOT EXISTS (SELECT 1 FROM crm.ProjectBillingMilestone WHERE ProjectId = @FfProjectId AND TriggerType = 'DATE' AND Amount = 2500.00)
    THROW 59043, N'Milestone save should store three milestones totalling the 10,000.00 fee (percent stored as amount).', 1;
SELECT @DateMsId = Id FROM crm.ProjectBillingMilestone WHERE ProjectId = @FfProjectId AND TriggerType = 'DATE';
SELECT @ManualMsId = Id FROM crm.ProjectBillingMilestone WHERE ProjectId = @FfProjectId AND TriggerType = 'MANUAL';

-- Only the date milestone is ready
EXEC ar.usp_InvoiceRun_Generate @PeriodEnd = @Today, @ProjectId = @FfProjectId, @InvoiceRunId = @FfRunId OUTPUT;
SELECT @FfInvoiceId = Id FROM ar.Invoice WHERE TenantId = @TenantId AND InvoiceRunId = @FfRunId;
IF @FfInvoiceId IS NULL OR NOT EXISTS (SELECT 1 FROM ar.Invoice WHERE Id = @FfInvoiceId AND SubTotal = 2500.00)
   OR (SELECT COUNT(*) FROM ar.InvoiceEntry AS ie
       JOIN lkp.InvoiceLineType AS lt ON lt.TenantId = ie.TenantId AND lt.Id = ie.LineTypeId
       WHERE ie.InvoiceId = @FfInvoiceId AND lt.SystemCode = 'FIXED_FEE') <> 1
   OR NOT EXISTS (SELECT 1 FROM crm.ProjectBillingMilestone WHERE Id = @DateMsId AND InvoiceEntryId IS NOT NULL)
    THROW 59044, N'First run should bill only the 2,500.00 date milestone as one FIXED_FEE line.', 1;

-- Sign off the manual milestone and finish the task, then delete the draft and rerun: all three bill
EXEC crm.usp_ProjectMilestone_Complete @MilestoneId = @ManualMsId;
UPDATE t SET TaskStatusId = s.Id
FROM crm.ClientTask AS t JOIN lkp.TaskStatus AS s ON s.TenantId = t.TenantId AND s.SystemCode = 'DONE'
WHERE t.Id = @FfTaskId;
EXEC ar.usp_Invoice_DeleteDraft @InvoiceRunId = @FfRunId;
IF EXISTS (SELECT 1 FROM crm.ProjectBillingMilestone WHERE Id = @DateMsId AND InvoiceEntryId IS NOT NULL)
    THROW 59045, N'Deleting the draft did not release the milestone.', 1;

EXEC ar.usp_InvoiceRun_Generate @PeriodEnd = @Today, @ProjectId = @FfProjectId, @InvoiceRunId = @FfRunId2 OUTPUT;
IF NOT EXISTS (SELECT 1 FROM ar.Invoice WHERE TenantId = @TenantId AND InvoiceRunId = @FfRunId2 AND SubTotal = 10000.00)
   OR EXISTS (SELECT 1 FROM crm.ProjectBillingMilestone WHERE ProjectId = @FfProjectId AND InvoiceEntryId IS NULL)
    THROW 59046, N'Rerun should bill all three milestones for 10,000.00.', 1;
PRINT 'ok 15 fixed fee: date milestone billed first; task and manual milestones billed once ready (10,000.00)';

------------------------------------------------------------------ 16. MFA recovery code: used once, then refused
EXEC sp_set_session_context N'UserId', @UserId;
EXEC sec.usp_Auth_SetMfa @MfaSecretEncrypted = 0x0102, @RecoveryCodeHashes = N'["smoke-code-a","smoke-code-b"]';
DECLARE @Recovery TABLE (Used BIT, CodesRemaining INT);
INSERT INTO @Recovery EXEC sec.usp_Auth_UseRecoveryCode @AppUserId = @UserId, @CodeHash = 'smoke-code-a';
INSERT INTO @Recovery EXEC sec.usp_Auth_UseRecoveryCode @AppUserId = @UserId, @CodeHash = 'smoke-code-a';
IF (SELECT COUNT(*) FROM @Recovery WHERE Used = 1 AND CodesRemaining = 1) <> 1
   OR (SELECT COUNT(*) FROM @Recovery WHERE Used = 0) <> 1
   OR NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @UserId AND RecoveryCodeHashes = N'["smoke-code-b"]' AND MfaEnabledAt IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM sec.LoginAudit WHERE AppUserId = @UserId AND EventType = 'MFA_RECOVERY_USED')
   OR (SELECT COUNT(*) FROM sec.LoginAudit WHERE AppUserId = @UserId AND EventType = 'MFA_FAIL') <> 1
   OR NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @UserId AND FailedAttempts = 1)
    THROW 59060, N'usp_Auth_UseRecoveryCode should accept a code once, refuse it the second time and keep MFA enabled.', 1;
PRINT 'ok 16 recovery code used once, refused on reuse (counted toward lockout); MFA stayed on';

------------------------------------------------------------------ 17. Weekly timesheet, plan features, UI preferences, recent items
DECLARE @TsTaskId INT, @TsTaskKey VARCHAR(20), @TsDay DATE = DATEADD(DAY, -21, @WorkDate), @Ts INT, @Ts2 INT,
        @TsE1 INT, @TsE2 INT, @TsE3 INT, @TsStatus VARCHAR(30), @Feat NVARCHAR(400), @FeatSource VARCHAR(10),
        @Rid UNIQUEIDENTIFIER;
EXEC sp_set_session_context N'UserId', @UserId;
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'TimeEntry.RequireApproval', @Value = N'1';  -- contractor default is 0
EXEC crm.usp_ClientTask_Create @ProjectId = @ProjectId, @Title = N'Timesheet task', @TaskId = @TsTaskId OUTPUT, @TaskKey = @TsTaskKey OUTPUT;

EXEC crm.usp_TimeEntry_Save @TimeEntryId = @TsE1 OUTPUT, @TaskId = @TsTaskId, @WorkDate = @TsDay, @Minutes = 60, @Description = N'Week work 1';
EXEC crm.usp_TimeEntry_Save @TimeEntryId = @TsE2 OUTPUT, @TaskId = @TsTaskId, @WorkDate = @TsDay, @Minutes = 30, @Description = N'Week work 2';
SELECT @Ts = TimesheetId FROM crm.TimeEntry WHERE Id = @TsE1;
SELECT @Ts2 = TimesheetId FROM crm.TimeEntry WHERE Id = @TsE2;
IF @Ts IS NULL OR @Ts <> @Ts2
   OR NOT EXISTS (SELECT 1 FROM crm.Timesheet WHERE Id = @Ts AND AppUserId = @UserId AND DATEDIFF(DAY, '19000101', WeekStart) % 7 = 0
                  AND WeekEnd = DATEADD(DAY, 6, WeekStart) AND @TsDay BETWEEN WeekStart AND WeekEnd)
    THROW 59070, N'Both entries should be filed on one Monday-to-Sunday timesheet covering the work date.', 1;

EXEC crm.usp_Timesheet_Submit @TimesheetId = @Ts;
SELECT @TsStatus = s.SystemCode FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId WHERE t.Id = @Ts;
IF @TsStatus <> 'SUBMITTED' THROW 59071, N'Submitting the week should leave it SUBMITTED.', 1;

EXEC crm.usp_Timesheet_Reject @TimesheetId = @Ts, @Reason = N'Split the second entry';
SELECT @TsStatus = s.SystemCode FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId WHERE t.Id = @Ts;
IF @TsStatus <> 'REJECTED' OR EXISTS (SELECT 1 FROM crm.TimeEntry WHERE TimesheetId = @Ts AND RejectedReason IS NULL)
    THROW 59072, N'Rejecting the week should send every entry back with the reason.', 1;

EXEC crm.usp_Timesheet_Submit @TimesheetId = @Ts;
EXEC crm.usp_TimeEntry_Reject @TimeEntryId = @TsE2, @Reason = N'Wrong task';     -- one entry sent back
SELECT @TsStatus = s.SystemCode FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId WHERE t.Id = @Ts;
IF @TsStatus <> 'REJECTED' THROW 59073, N'Rejecting one entry should show the week as REJECTED.', 1;

EXEC crm.usp_TimeEntry_Save @TimeEntryId = @TsE2 OUTPUT, @TaskId = @TsTaskId, @WorkDate = @TsDay, @Minutes = 45, @Description = N'Week work 2, fixed';
EXEC crm.usp_Timesheet_Submit @TimesheetId = @Ts;
EXEC crm.usp_TimeEntry_Save @TimeEntryId = @TsE3 OUTPUT, @TaskId = @TsTaskId, @WorkDate = @TsDay, @Minutes = 15, @Description = N'Late addition';
SELECT @TsStatus = s.SystemCode FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId WHERE t.Id = @Ts;
IF @TsStatus <> 'OPEN' OR (SELECT TimesheetId FROM crm.TimeEntry WHERE Id = @TsE3) <> @Ts
    THROW 59074, N'Adding time to a submitted week (AllowResubmit on) should reopen it.', 1;

EXEC crm.usp_Timesheet_Submit @TimesheetId = @Ts;
EXEC crm.usp_Timesheet_Approve @TimesheetId = @Ts;
SELECT @TsStatus = s.SystemCode FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId WHERE t.Id = @Ts;
IF @TsStatus <> 'APPROVED'
   OR (SELECT COUNT(*) FROM crm.TimeEntry AS e JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
       WHERE e.TimesheetId = @Ts AND s.SystemCode = 'APPROVED' AND e.RateApplied = @Rate) <> 3
    THROW 59075, N'Approving the week should approve all three entries at the user rate.', 1;

-- plan-driven features
SELECT @Feat = Value, @FeatSource = Source FROM admin.fn_Setting(@TenantId, NULL, 'Feature.Pilo');
IF @Feat <> N'0' OR @FeatSource <> 'DEFAULT' THROW 59076, N'Feature.Pilo should be off on the Flat plan.', 1;
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'AI_PLUS') WHERE Id = @TenantId;
SELECT @Feat = Value, @FeatSource = Source FROM admin.fn_Setting(@TenantId, NULL, 'Feature.ExtendedBranding');
IF @Feat <> N'1' OR @FeatSource <> 'PLAN' THROW 59077, N'AI Powered Plus should turn on Feature.ExtendedBranding from the plan.', 1;
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'STANDARD') WHERE Id = @TenantId;

-- UI preferences and recent items
EXEC admin.usp_UserPreference_Set @PrefKey = 'ui.theme', @Value = N'"dark"';
EXEC admin.usp_UserPreference_Set @PrefKey = 'ui.navOrder', @Value = N'["today","time","clients"]';
EXEC admin.usp_UserPreference_Set @PrefKey = 'ui.theme', @Value = N'"light"';
EXEC admin.usp_UserPreference_Set @PrefKey = 'ui.navOrder', @Value = NULL;
IF NOT EXISTS (SELECT 1 FROM admin.UserPreference WHERE TenantId = @TenantId AND AppUserId = @UserId AND PrefKey = 'ui.theme' AND Value = N'"light"')
   OR EXISTS (SELECT 1 FROM admin.UserPreference WHERE TenantId = @TenantId AND AppUserId = @UserId AND PrefKey = 'ui.navOrder')
    THROW 59078, N'UI preferences should upsert and delete on NULL.', 1;
SET @i = 0;
WHILE @i < 27
BEGIN
    SET @Rid = NEWID();
    EXEC sec.usp_RecentItem_Touch @EntityType = 'client', @EntityPublicId = @Rid, @Title = N'Recent';
    SET @i += 1;
END;
IF (SELECT COUNT(*) FROM sec.UserRecentItem WHERE TenantId = @TenantId AND AppUserId = @UserId) <> 25
    THROW 59079, N'Recent items should keep only the newest 25.', 1;
PRINT 'ok 17 timesheet submitted, rejected, resubmitted, reopened and approved (3 entries); plan features; preferences; recent items';

------------------------------------------------------------------ Done
IF @Keep = 1 COMMIT; ELSE ROLLBACK;
EXEC sp_set_session_context N'TenantId', NULL;
EXEC sp_set_session_context N'UserId', NULL;
PRINT CONCAT('Smoke test passed. ', IIF(@Keep = 1, 'Rows kept for TenantId ', 'Rolled back; TenantId was '), @TenantId, '.');
