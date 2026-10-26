/*
Smoke test: run against a freshly published Pillar database (SQL Server 2019+), in SSMS or sqlcmd.
Walks one tenant through the billing path end to end:
  tenant sign-up -> client (default billing profile) -> contact (billing contact) -> project, user, rate
  -> task -> time entry (save, submit, auto-approve) -> invoice run -> issue (number, fee) -> rendering data -> payments (partial, paid, voided) -> invoice void (fee reversal)
  -> vendor bill (auto-approve, pay) -> billable expense rebilled on the next run -> draft deleted
  -> Pillar monthly statement (generate, minimum, card charge failed then paid)
  -> no-login subcontractor with owner-entered time, invited to log in, sign-in lockout
  -> fixed-fee milestones -> MFA recovery code -> weekly timesheet approval, plan features, UI preferences, recent items
  -> custom fields (define, fill in, clear, retire a pick-list choice, reorder)
  -> notifications, watchers, comments with mentions, checklist, client notes and feed, budget alert, project setup
  -> configurable setup checks gating Planned -> task details edit with change comment
  -> timesheet approval tabs, approver edits, saved Pilo reports, custom roles
  -> data-driven permission grid, canned report cards, Pilo render type
  -> per-page settings permissions, MFA policy, audit log, profile, sessions, email change, CSV import, notification channels
  -> seats, plan changes, plan/seat/Pilo statement lines, failed charge and mark paid, suspend, support access and sign-in as,
     support tickets, announcements, help articles, sample company.
  -> Today layouts per role, weekly hours goal, weekly expense reports with the timesheet and Pilo receipt reads, search, contacts.
Step 1 signs up the way the app does since handoff 22: terms accepted, email verified, application sent, then approved by Pillar.
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

------------------------------------------------------------------ 1. Tenant sign-up (terms, verify email, apply, Pillar approves)
DECLARE @TosId INT, @TosVersion NVARCHAR(20) = CONCAT(N'smoke-', LEFT(CONVERT(NVARCHAR(36), NEWID()), 8)),
        @Verify BINARY(32) = HASHBYTES('SHA2_256', CONCAT('verify', NEWID()));
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC admin.usp_LegalDocument_Publish @Code = 'TOS', @Version = @TosVersion, @Title = N'Smoke test terms', @Body = N'<p>Terms</p>',
     @DocumentId = @TosId OUTPUT;
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;

EXEC admin.usp_Tenant_SignUp @TenantName = N'Smoke Test Tenant', @OwnerEmail = @OwnerEmail, @OwnerFirstName = N'Smoke',
     @OwnerLastName = N'Owner', @PasswordHash = '$2b$12$smoke.test.hash.not.a.real.bcrypt.value.........',
     @TenantTypeCode = 'CONTRACTOR', @TenantId = @TenantId OUTPUT, @AppUserId = @UserId OUTPUT,
     @TermsDocumentId = @TosId, @VerifyTokenHash = @Verify, @IpAddress = '203.0.113.9';
IF @TenantId IS NULL OR @UserId IS NULL THROW 59001, N'Sign-up did not create the tenant and owner. Are the post-deploy seeds in place?', 1;
EXEC sp_set_session_context N'UserId', @UserId;    -- sign-up already set TenantId

IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId AND Status = 'SETUP')
   OR NOT EXISTS (SELECT 1 FROM sec.UserLegalAcceptance WHERE AppUserId = @UserId AND DocumentId = @TosId AND IpAddress = '203.0.113.9')
   OR EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @UserId AND EmailVerifiedAt IS NOT NULL)
    THROW 59128, N'Sign-up should start in SETUP with the terms accepted and the email not yet verified.', 1;
CREATE TABLE #Verified (AppUserId INT, TenantId INT);
INSERT INTO #Verified EXEC sec.usp_Auth_VerifyEmail @TokenHash = @Verify;
INSERT INTO #Verified EXEC sec.usp_Auth_VerifyEmail @TokenHash = @Verify;    -- used: no row
IF (SELECT COUNT(*) FROM #Verified WHERE AppUserId = @UserId) <> 1
   OR NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @UserId AND EmailVerifiedAt IS NOT NULL)
    THROW 59129, N'The verify link should verify the email once.', 1;
DROP TABLE #Verified;

EXEC admin.usp_Tenant_SubmitApplication @RequestedPlanCode = 'STANDARD', @Note = N'Smoke test application';
IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId AND Status = 'PENDING_REVIEW' AND SubmittedAt IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformNotification WHERE TenantId = @TenantId AND Kind = 'APPLICATION_SUBMITTED'
                  AND SendEmail = 1 AND JSON_VALUE(DataJson, '$.ownerEmail') = @OwnerEmail)
    THROW 59130, N'Submitting should put the tenant in review and tell Pillar who applied.', 1;

CREATE TABLE #Owners (Email NVARCHAR(254), FirstName NVARCHAR(100), DisplayName NVARCHAR(300));
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
INSERT INTO #Owners EXEC admin.usp_Tenant_Approve @TenantId = @TenantId, @Note = N'Smoke test';
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId AND Status = 'ACTIVE' AND ApprovedAt IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM #Owners WHERE Email = @OwnerEmail)
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformAudit WHERE TenantId = @TenantId AND Action = 'APPROVE')
   OR EXISTS (SELECT 1 FROM admin.PlatformNotification WHERE TenantId = @TenantId AND ReadAt IS NULL)
    THROW 59131, N'Approval should make the tenant ACTIVE, return the owner for the welcome email and clear the inbox item.', 1;
DROP TABLE #Owners;

IF NOT EXISTS (SELECT 1 FROM sec.AppUser AS u JOIN sec.Role AS r ON r.TenantId = u.TenantId AND r.Id = u.RoleId
               WHERE u.Id = @UserId AND r.Code = 'OWNER' AND u.Status = 'ACTIVE')
   OR (SELECT COUNT(*) FROM sec.Role WHERE TenantId = @TenantId) <> 5
   OR NOT EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'billing.manage'))
    THROW 59037, N'Sign-up should create five roles and an active owner holding every permission.', 1;

IF NOT EXISTS (SELECT 1 FROM lkp.ClientStatus WHERE TenantId = @TenantId AND SystemCode = 'ACTIVE')
    THROW 59002, N'Lookup sync did not copy ClientStatus to the tenant.', 1;
IF NOT EXISTS (SELECT 1 FROM ar.InvoiceLayout WHERE TenantId = @TenantId AND Code = N'SUMMARY' AND IsDefault = 1)
    THROW 59028, N'Invoice layouts were not seeded (is admin.Report seeded?).', 1;
PRINT 'ok 1  signed up: terms, verified email, application, approval; tenant, owner, roles, lookups, settings and invoice layouts';

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

------------------------------------------------------------------ 4. Hourly project (100 budget hours), project user, rate
INSERT INTO crm.ClientProject (TenantId, ClientId, BillingProfileId, ProjectCode, Name, ProjectTypeId, BillingTypeId, ProjectStatusId, BudgetHours)
SELECT @TenantId, @ClientId, @ProfileId, N'SMOKE-1', N'Smoke Test Project', pt.Id, bt.Id, ps.Id, 100
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
INSERT INTO crm.ProjectUser (TenantId, ProjectId, AppUserId) VALUES (@TenantId, @FfProjectId, @UserId);  -- tasks need a team
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
IF @Feat <> N'0' OR @FeatSource <> 'DEFAULT' THROW 59077, N'Extended branding is Enterprise only, so AI Powered Plus should leave it off.', 1;
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'ENTERPRISE') WHERE Id = @TenantId;
SELECT @Feat = Value, @FeatSource = Source FROM admin.fn_Setting(@TenantId, NULL, 'Feature.ExtendedBranding');
IF @Feat <> N'1' OR @FeatSource <> 'PLAN' THROW 59077, N'Enterprise should turn on Feature.ExtendedBranding from the plan.', 1;
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

------------------------------------------------------------------ 18. Custom fields: define, fill in, clear, retire a choice, reorder
DECLARE @PoFieldId INT, @SeatsFieldId INT, @DealFieldId INT, @GoLiveFieldId INT, @SignedFieldId INT,
        @NewOptId INT, @RenewalOptId INT, @CfValues NVARCHAR(MAX), @CfOptions NVARCHAR(MAX);

EXEC admin.usp_CustomField_Save @FieldId = @PoFieldId OUTPUT, @EntityType = 'CLIENT', @FieldKey = 'po_reference',
     @Label = N'PO reference', @DataType = 'TEXT', @MaxLength = 20, @IsRequired = 1, @ShowInList = 1;
EXEC admin.usp_CustomField_Save @FieldId = @SeatsFieldId OUTPUT, @EntityType = 'CLIENT', @FieldKey = 'seats',
     @Label = N'Seats', @DataType = 'INT';
EXEC admin.usp_CustomField_Save @FieldId = @DealFieldId OUTPUT, @EntityType = 'CLIENT', @FieldKey = 'deal_type',
     @Label = N'Deal type', @DataType = 'LIST', @Options = N'[{"label":"New"},{"label":"Renewal"}]';
EXEC admin.usp_CustomField_Save @FieldId = @GoLiveFieldId OUTPUT, @EntityType = 'CLIENT', @FieldKey = 'go_live',
     @Label = N'Go-live', @DataType = 'DATE';
EXEC admin.usp_CustomField_Save @FieldId = @SignedFieldId OUTPUT, @EntityType = 'CLIENT', @FieldKey = 'signed',
     @Label = N'Contract signed', @DataType = 'BIT';
SELECT @NewOptId = Id FROM admin.CustomFieldOption WHERE FieldId = @DealFieldId AND Label = N'New';
SELECT @RenewalOptId = Id FROM admin.CustomFieldOption WHERE FieldId = @DealFieldId AND Label = N'Renewal';
IF (SELECT COUNT(*) FROM admin.CustomFieldDefinition WHERE TenantId = @TenantId AND EntityType = 'CLIENT') <> 5
   OR @NewOptId IS NULL OR @RenewalOptId IS NULL
    THROW 59080, N'Five client custom fields and two pick-list choices should exist.', 1;

SET @CfValues = CONCAT(N'{"po_reference":"A-1207","seats":12,"deal_type":', @NewOptId, N',"go_live":"2026-11-01","signed":true}');
EXEC admin.usp_CustomFieldValues_Save @EntityType = 'CLIENT', @RecordId = @ClientId, @Values = @CfValues;
IF (SELECT COUNT(*) FROM admin.vw_CustomFieldValue WHERE EntityType = 'CLIENT' AND RecordId = @ClientId) <> 5
   OR NOT EXISTS (SELECT 1 FROM admin.vw_CustomFieldValue WHERE RecordId = @ClientId AND FieldKey = 'deal_type' AND DisplayValue = N'New')
   OR NOT EXISTS (SELECT 1 FROM admin.vw_CustomFieldValue WHERE RecordId = @ClientId AND FieldKey = 'seats' AND ValueInt = 12)
   OR NOT EXISTS (SELECT 1 FROM admin.vw_CustomFieldValue WHERE RecordId = @ClientId AND FieldKey = 'go_live' AND ValueDate = '2026-11-01')
    THROW 59081, N'Saving the client''s custom fields should store five typed values.', 1;

EXEC admin.usp_CustomFieldValues_Save @EntityType = 'CLIENT', @RecordId = @ClientId, @Values = N'{"seats":null,"po_reference":"A-1208"}';
IF EXISTS (SELECT 1 FROM admin.CustomFieldValue WHERE RecordId = @ClientId AND FieldId = @SeatsFieldId)
   OR NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue WHERE RecordId = @ClientId AND FieldId = @PoFieldId AND ValueText = N'A-1208')
   OR NOT EXISTS (SELECT 1 FROM admin.CustomFieldValue WHERE RecordId = @ClientId AND FieldId = @SignedFieldId AND ValueBit = 1)
    THROW 59082, N'A partial save should clear seats, change the PO and leave the other fields alone.', 1;

-- drop "New" from the list: it is in use, so it is retired and the client still shows it
SET @CfOptions = CONCAT(N'[{"id":', @RenewalOptId, N',"label":"Renewal"},{"label":"Expansion"}]');
EXEC admin.usp_CustomField_Save @FieldId = @DealFieldId, @EntityType = 'CLIENT', @FieldKey = 'deal_type',
     @Label = N'Deal type', @DataType = 'LIST', @Options = @CfOptions;
CREATE TABLE #Cf (FieldId INT, FieldKey VARCHAR(50), Label NVARCHAR(100), DataType VARCHAR(10), MaxLength INT, IsRequired BIT,
                  HelpText NVARCHAR(400), SortOrder INT, ShowInList BIT, ValueText NVARCHAR(400), ValueInt BIGINT,
                  ValueDecimal DECIMAL(19,4), ValueDate DATE, ValueBit BIT, OptionId INT, DisplayValue NVARCHAR(400), Options NVARCHAR(MAX));
INSERT INTO #Cf EXEC admin.usp_CustomFieldValues_Get @EntityType = 'CLIENT', @RecordId = @ClientId;
IF NOT EXISTS (SELECT 1 FROM admin.CustomFieldOption WHERE Id = @NewOptId AND IsActive = 0)
   OR NOT EXISTS (SELECT 1 FROM #Cf WHERE FieldKey = 'deal_type' AND DisplayValue = N'New'
                  AND (SELECT COUNT(*) FROM OPENJSON(Options)) = 3)
   OR (SELECT COUNT(*) FROM #Cf) <> 5
    THROW 59083, N'Retiring a used choice should keep it on the record and in that record''s choices.', 1;
DROP TABLE #Cf;

SET @CfOptions = CONCAT(N'[', @GoLiveFieldId, N',', @PoFieldId, N']');
EXEC admin.usp_CustomField_Reorder @EntityType = 'CLIENT', @FieldIds = @CfOptions;
IF (SELECT TOP (1) Id FROM admin.CustomFieldDefinition WHERE TenantId = @TenantId AND EntityType = 'CLIENT' ORDER BY SortOrder) <> @GoLiveFieldId
    THROW 59084, N'Reorder should put Go-live first.', 1;
PRINT 'ok 18 custom fields: five client fields saved, partly cleared, a used choice retired, reordered';

------------------------------------------------------------------ 19. Notifications, watchers, comments, checklist, notes, budget alert, project setup
-- The subcontractor from step 14 (now an active login) becomes the client's account manager and SMOKE-1's project manager.
DECLARE @NtTaskId INT, @NtTaskKey VARCHAR(20), @NtCommentId INT, @NtNoteId INT, @NtSetupProjectId INT,
        @NtMentions NVARCHAR(100) = CONCAT(N'[', @SubId, N']'), @NtUnread INT, @NtCount INT;
UPDATE crm.Client SET AccountManagerUserId = @SubId WHERE Id = @ClientId;
UPDATE crm.ClientProject SET ProjectManagerUserId = @SubId WHERE Id = @ProjectId;

EXEC crm.usp_ClientTask_Create @ProjectId = @ProjectId, @Title = N'Notify me', @AssignedUserId = @SubId,
     @StepsToReplicate = N'<p>Open the page</p>', @ResolutionCriteria = N'<p>It loads</p>',
     @TaskId = @NtTaskId OUTPUT, @TaskKey = @NtTaskKey OUTPUT;
IF (SELECT COUNT(*) FROM crm.TaskWatcher WHERE TaskId = @NtTaskId AND AppUserId IN (@UserId, @SubId)) <> 2
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'TASK_ASSIGNED_TO_ME' AND EntityId = @NtTaskId)
   OR EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'TASK_CREATED_ON_MY_PROJECT')
   OR EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @UserId)
    THROW 59085, N'New task: assignee and reporter should watch it; only TASK_ASSIGNED_TO_ME (on by default) should reach the assignee, and nothing the owner did should notify the owner.', 1;

EXEC crm.usp_TaskComment_Save @CommentId = @NtCommentId OUTPUT, @TaskId = @NtTaskId,
     @Body = N'<p>Can you look at this?</p>', @MentionUserIds = @NtMentions;
UPDATE t SET TaskStatusId = s.Id
FROM crm.ClientTask AS t JOIN lkp.TaskStatus AS s ON s.TenantId = t.TenantId AND s.SystemCode = 'IN_PROGRESS'
WHERE t.Id = @NtTaskId;
IF NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'MENTIONED' AND EntityType = 'COMMENT' AND EntityId = @NtCommentId)
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'WATCHED_TASK_CHANGED' AND EntityId = @NtTaskId)
   OR NOT EXISTS (SELECT 1 FROM crm.TaskCommentMention WHERE CommentId = @NtCommentId AND AppUserId = @SubId)
    THROW 59086, N'A mention and a status change should notify the mentioned watcher.', 1;

EXEC crm.usp_TaskChecklist_Save @TaskId = @NtTaskId, @Items = N'[{"text":"Reproduce","isDone":true},{"text":"Fix"}]';
IF (SELECT COUNT(*) FROM crm.TaskChecklistItem WHERE TaskId = @NtTaskId) <> 2
   OR NOT EXISTS (SELECT 1 FROM crm.TaskChecklistItem WHERE TaskId = @NtTaskId AND ItemText = N'Reproduce' AND DoneBy = @UserId AND DoneAt IS NOT NULL)
    THROW 59087, N'Checklist save should store two items and stamp the checked one.', 1;

EXEC crm.usp_ClientNote_Save @NoteId = @NtNoteId OUTPUT, @ClientId = @ClientId, @ContactId = @ContactId,
     @NoteTypeId = NULL, @Subject = N'Kickoff call', @Body = N'<p>Went well.</p>', @MentionUserIds = @NtMentions;
UPDATE n SET NoteTypeId = t.Id FROM crm.ClientNote AS n JOIN lkp.NoteType AS t ON t.TenantId = n.TenantId AND t.SystemCode = 'CALL'
WHERE n.Id = @NtNoteId;
IF NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'MENTIONED' AND EntityType = 'NOTE' AND EntityId = @NtNoteId)
   OR NOT EXISTS (SELECT 1 FROM crm.vw_ClientActivity WHERE ClientId = @ClientId AND ActivityType = 'NOTE_CALL' AND Title = N'Kickoff call')
   OR NOT EXISTS (SELECT 1 FROM crm.vw_ClientActivity WHERE ClientId = @ClientId AND ActivityType = 'INVOICE_ISSUED')
   OR NOT EXISTS (SELECT 1 FROM crm.vw_ClientActivity WHERE ClientId = @ClientId AND ActivityType = 'PAYMENT_RECEIVED')
    THROW 59088, N'Client note should notify the mention and show in the activity feed with invoices and payments.', 1;

-- budget: alert at 1% of SMOKE-1's 100 hours; a second check must not repeat it
UPDATE crm.ClientProject SET BudgetAlertPercents = '1' WHERE Id = @ProjectId;
EXEC crm.usp_Project_CheckBudgetAlerts @ProjectId = @ProjectId;
EXEC crm.usp_Project_CheckBudgetAlerts @ProjectId = @ProjectId;
IF NOT EXISTS (SELECT 1 FROM crm.ProjectBudgetAlert WHERE ProjectId = @ProjectId AND Basis = 'HOURS' AND ThresholdPercent = 1)
   OR (SELECT COUNT(*) FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'BUDGET_THRESHOLD' AND EntityId = @ProjectId) <> 1
    THROW 59089, N'Crossing 1% of budget hours should notify the project manager once.', 1;

-- the subcontractor's bell, read as them
EXEC sp_set_session_context N'UserId', @SubId;
CREATE TABLE #Bell (Id BIGINT, NotificationType VARCHAR(40), TypeName NVARCHAR(100), Title NVARCHAR(200), Body NVARCHAR(1000),
                    EntityType VARCHAR(20), EntityId INT, ActorUserId INT, ActorName NVARCHAR(201), CreatedAt DATETIME2(0), ReadAt DATETIME2(0), ActionKind VARCHAR(20));
INSERT INTO #Bell EXEC sec.usp_Notification_List @UnreadCount = @NtUnread OUTPUT;
EXEC sec.usp_NotificationSetting_Set @Settings = N'{"TASK_CREATED_ON_MY_PROJECT": true, "INVOICE_PAID": false}';
EXEC sec.usp_Notification_MarkRead;
SELECT @NtCount = COUNT(*) FROM sec.Notification WHERE AppUserId = @SubId AND ReadAt IS NULL;
EXEC sp_set_session_context N'UserId', @UserId;
IF @NtUnread < 5 OR (SELECT COUNT(*) FROM #Bell) <> @NtUnread OR @NtCount <> 0
   OR NOT EXISTS (SELECT 1 FROM sec.UserNotificationSetting WHERE AppUserId = @SubId AND NotificationType = 'TASK_CREATED_ON_MY_PROJECT' AND IsOn = 1)
    THROW 59090, N'The bell should list five unread notifications, then mark them all read; settings should save.', 1;
DROP TABLE #Bell;

-- setup: a bare hourly project is missing team, rate and budget, and refuses tasks until they are added
INSERT INTO crm.ClientProject (TenantId, ClientId, BillingProfileId, ProjectCode, Name, ProjectTypeId, BillingTypeId, ProjectStatusId)
SELECT @TenantId, @ClientId, @ProfileId, N'SMOKE-SU', N'Smoke Setup Project', pt.Id, bt.Id, ps.Id
FROM lkp.ProjectType AS pt
JOIN lkp.BillingType AS bt ON bt.TenantId = pt.TenantId AND bt.SystemCode = 'HOURLY'
JOIN lkp.ProjectStatus AS ps ON ps.TenantId = pt.TenantId AND ps.SystemCode = 'OPEN'
WHERE pt.TenantId = @TenantId AND pt.Code = N'PM';
SET @NtSetupProjectId = SCOPE_IDENTITY();
IF (SELECT STRING_AGG(Code, ',') WITHIN GROUP (ORDER BY SortOrder) FROM crm.fn_ProjectSetupIssues(@TenantId, @NtSetupProjectId)) <> 'TEAM,RATE,BUDGET'
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'PROJECT_CREATED_ON_MY_CLIENT' AND EntityId = @NtSetupProjectId)
    THROW 59091, N'A bare hourly project should be missing TEAM, RATE and BUDGET, and its creation should notify the account manager.', 1;
UPDATE crm.ClientProject SET DefaultRate = 100, BudgetAmount = 5000 WHERE Id = @NtSetupProjectId;
INSERT INTO crm.ProjectUser (TenantId, ProjectId, AppUserId) VALUES (@TenantId, @NtSetupProjectId, @UserId);
IF EXISTS (SELECT 1 FROM crm.fn_ProjectSetupIssues(@TenantId, @NtSetupProjectId))
    THROW 59092, N'With a team, rate and budget the project should be ready.', 1;
PRINT 'ok 19 notifications (assign, mention, status, note, budget, new project), watchers, checklist, client feed, project setup';

------------------------------------------------------------------ 20. Configurable setup checks gate leaving Planned
DECLARE @PlProjectId INT;
EXEC admin.usp_ProjectSetupCheck_Set @Levels = N'{"PROJECT_MANAGER":"BLOCK","PO_NUMBER":"WARN","BUDGET":"OFF"}';
CREATE TABLE #Checks (Code VARCHAR(30), Name NVARCHAR(100), Description NVARCHAR(400), AppliesTo VARCHAR(100),
                      DefaultLevel VARCHAR(5), Level VARCHAR(5), SortOrder INT);
INSERT INTO #Checks EXEC admin.usp_ProjectSetupCheck_Get;
IF (SELECT COUNT(*) FROM #Checks) <> 11
   OR NOT EXISTS (SELECT 1 FROM #Checks WHERE Code = 'PROJECT_MANAGER' AND Level = 'BLOCK' AND DefaultLevel = 'OFF')
   OR NOT EXISTS (SELECT 1 FROM #Checks WHERE Code = 'BUDGET' AND Level = 'OFF')
    THROW 59093, N'Setup check levels should save over the 11-check catalog.', 1;
DROP TABLE #Checks;

INSERT INTO crm.ClientProject (TenantId, ClientId, BillingProfileId, ProjectCode, Name, ProjectTypeId, BillingTypeId, ProjectStatusId, DefaultRate)
SELECT @TenantId, @ClientId, @ProfileId, N'SMOKE-PL', N'Smoke Planned Project', pt.Id, bt.Id, ps.Id, 120
FROM lkp.ProjectType AS pt
JOIN lkp.BillingType AS bt ON bt.TenantId = pt.TenantId AND bt.SystemCode = 'HOURLY'
JOIN lkp.ProjectStatus AS ps ON ps.TenantId = pt.TenantId AND ps.SystemCode = 'PLANNED'
WHERE pt.TenantId = @TenantId AND pt.Code = N'PM';
SET @PlProjectId = SCOPE_IDENTITY();
INSERT INTO crm.ProjectUser (TenantId, ProjectId, AppUserId) VALUES (@TenantId, @PlProjectId, @UserId);
IF (SELECT STRING_AGG(CONCAT(Code, ':', Severity), ',') WITHIN GROUP (ORDER BY SortOrder) FROM crm.fn_ProjectSetupIssues(@TenantId, @PlProjectId))
   <> 'PROJECT_MANAGER:BLOCK,PO_NUMBER:WARN'
    THROW 59094, N'The planned project should be blocked only by the missing project manager, warned about the PO, and not asked for a budget.', 1;

-- with a project manager it is ready and may leave Planned; the PO warning stays
UPDATE crm.ClientProject SET ProjectManagerUserId = @UserId WHERE Id = @PlProjectId;
UPDATE p SET ProjectStatusId = ps.Id
FROM crm.ClientProject AS p JOIN lkp.ProjectStatus AS ps ON ps.TenantId = p.TenantId AND ps.SystemCode = 'OPEN'
WHERE p.Id = @PlProjectId;
IF NOT EXISTS (SELECT 1 FROM crm.ClientProject AS p JOIN lkp.ProjectStatus AS ps ON ps.TenantId = p.TenantId AND ps.Id = p.ProjectStatusId
               WHERE p.Id = @PlProjectId AND ps.SystemCode = 'OPEN')
   OR EXISTS (SELECT 1 FROM crm.fn_ProjectSetupIssues(@TenantId, @PlProjectId) WHERE Severity = 'BLOCK')
    THROW 59095, N'A ready project should move from Planned to Open.', 1;

EXEC admin.usp_ProjectSetupCheck_Set @Levels = N'{"PROJECT_MANAGER":"OFF","PO_NUMBER":"OFF","BUDGET":"BLOCK"}';
IF EXISTS (SELECT 1 FROM admin.TenantProjectSetupCheck WHERE TenantId = @TenantId)
    THROW 59096, N'Setting every check back to its default should leave no tenant rows.', 1;
PRINT 'ok 20 setup checks: tenant levels saved, a planned project blocked until it had a project manager, then opened';

------------------------------------------------------------------ 21. Task details edit posts a comment with change chips
DECLARE @DetCommentId INT, @DetDue DATE = DATEADD(DAY, 14, @WorkDate);
UPDATE crm.ClientTask SET EstimatedHours = 6 WHERE Id = @NtTaskId;
EXEC crm.usp_ClientTask_UpdateDetails @TaskId = @NtTaskId, @EstimatedHours = 8, @DueDate = @DetDue,
     @Comment = N'<p>Bigger than we thought.</p>', @CommentId = @DetCommentId OUTPUT;
IF NOT EXISTS (SELECT 1 FROM crm.ClientTask WHERE Id = @NtTaskId AND EstimatedHours = 8 AND DueDate = @DetDue AND ModifiedBy = @UserId)
   OR NOT EXISTS (SELECT 1 FROM crm.TaskComment WHERE Id = @DetCommentId AND TaskId = @NtTaskId AND AuthorUserId = @UserId
                  AND Body = N'<p>Bigger than we thought.</p>'
                  AND JSON_VALUE(ChangeJson, '$[0].field') = N'Due date' AND JSON_VALUE(ChangeJson, '$[0].from') IS NULL
                  AND JSON_VALUE(ChangeJson, '$[1].field') = N'Estimate' AND JSON_VALUE(ChangeJson, '$[1].from') = N'6 h'
                  AND JSON_VALUE(ChangeJson, '$[1].to') = N'8 h' AND JSON_VALUE(ChangeJson, '$[2].field') IS NULL)
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'WATCHED_TASK_CHANGED'
                  AND EntityId = @NtTaskId AND ReadAt IS NULL)
    THROW 59097, N'A details edit should update the task, post one comment with Due date and Estimate chips, and tell the watchers.', 1;
PRINT 'ok 21 details edit: task updated, change comment with chips, watchers notified';

------------------------------------------------------------------ 22. Approvals tabs, approver edits, saved Pilo reports, custom roles
DECLARE @Appr TABLE (TimesheetId INT, PublicId UNIQUEIDENTIFIER, AppUserId INT, PersonName NVARCHAR(201), WeekStart DATE, WeekEnd DATE,
        StatusCode VARCHAR(30), IsComplete BIT, EntryCount INT, Hours DECIMAL(19,4), BillableHours DECIMAL(19,4),
        BillableAmount DECIMAL(19,2), InvoicedCount INT, SubmittedAt DATETIME2(0), ApprovedAt DATETIME2(0), ApprovedBy INT,
        ApprovedByName NVARCHAR(201), RejectedAt DATETIME2(0), RejectedReason NVARCHAR(500),
        ExpenseBillId INT, ExpenseBillNumber NVARCHAR(50), ExpenseStatus VARCHAR(30), ExpenseCount INT, ExpenseTotal DECIMAL(19,4));
DECLARE @SrIds TABLE (n INT IDENTITY(1,1), Id INT);
DECLARE @ChgId INT, @SrId INT, @SrShared INT, @PsId INT, @PsId2 INT,
        @SrRole INT, @MemberRole INT, @ApproveTabFrom DATE = DATEADD(DAY, -7, @TsDay), @ApproveTabTo DATE = DATEADD(DAY, 7, @TsDay);

-- step 17 left @Ts approved with three billable entries: it sits on the Approved tab, not Complete
INSERT INTO @Appr EXEC crm.usp_Timesheet_ListForApproval @Tab = 'APPROVED', @PeriodFrom = @ApproveTabFrom, @PeriodTo = @ApproveTabTo;
IF NOT EXISTS (SELECT 1 FROM @Appr WHERE TimesheetId = @Ts AND EntryCount = 3 AND IsComplete = 0 AND ApprovedBy = @UserId)
    THROW 59098, N'The approved week should be listed on the Approved tab with three entries.', 1;

-- an approved week can be sent back while none of it is invoiced
EXEC crm.usp_Timesheet_Reject @TimesheetId = @Ts, @Reason = N'Wrong week for the late addition';
DELETE FROM @Appr;
INSERT INTO @Appr EXEC crm.usp_Timesheet_ListForApproval @Tab = 'REJECTED', @PeriodFrom = @ApproveTabFrom, @PeriodTo = @ApproveTabTo;
IF NOT EXISTS (SELECT 1 FROM @Appr WHERE TimesheetId = @Ts AND StatusCode = 'REJECTED')
   OR EXISTS (SELECT 1 FROM crm.TimeEntry AS e JOIN lkp.TimeEntryStatus AS s ON s.TenantId = e.TenantId AND s.Id = e.TimeEntryStatusId
              WHERE e.TimesheetId = @Ts AND (s.SystemCode <> 'DRAFT' OR e.ApprovedAt IS NOT NULL))
    THROW 59099, N'Sending back an approved week should return every entry to draft and list it on the Rejected tab.', 1;
EXEC crm.usp_Timesheet_Submit @TimesheetId = @Ts;
EXEC crm.usp_Timesheet_Approve @TimesheetId = @Ts;

-- the approver fixes approved time in place; the rate stays frozen and the change is logged with chips
EXEC crm.usp_TimeEntry_Update @TimeEntryId = @TsE1, @BilledMinutes = 90, @IsBillable = 0,
     @Reason = N'Internal call, not billable', @ChangeId = @ChgId OUTPUT;
IF NOT EXISTS (SELECT 1 FROM crm.TimeEntry WHERE Id = @TsE1 AND BilledMinutes = 90 AND IsBillable = 0 AND RateApplied = @Rate
               AND EnteredMinutes = 60)
   OR NOT EXISTS (SELECT 1 FROM crm.TimeEntryChange WHERE Id = @ChgId AND TimeEntryId = @TsE1 AND ChangedBy = @UserId
                  AND Reason = N'Internal call, not billable'
                  AND JSON_VALUE(ChangeJson, '$[0].field') = N'Hours' AND JSON_VALUE(ChangeJson, '$[0].from') = N'1 h'
                  AND JSON_VALUE(ChangeJson, '$[0].to') = N'1.5 h' AND JSON_VALUE(ChangeJson, '$[1].field') = N'Billable'
                  AND JSON_VALUE(ChangeJson, '$[1].to') = N'No' AND JSON_VALUE(ChangeJson, '$[2].field') IS NULL)
    THROW 59100, N'Editing approved time should keep the rate and log Hours and Billable chips with the reason.', 1;
EXEC crm.usp_TimeEntry_Update @TimeEntryId = @TsE1, @BilledMinutes = 90, @Reason = N'No change', @ChangeId = @ChgId OUTPUT;
IF @ChgId IS NOT NULL THROW 59101, N'An edit that changes nothing should not be logged.', 1;

-- with no billable time left to invoice the week counts as complete
EXEC crm.usp_TimeEntry_Update @TimeEntryId = @TsE2, @IsBillable = 0, @Reason = N'Covered by the fixed fee';
EXEC crm.usp_TimeEntry_Update @TimeEntryId = @TsE3, @IsBillable = 0, @Reason = N'Covered by the fixed fee';
DELETE FROM @Appr;
INSERT INTO @Appr EXEC crm.usp_Timesheet_ListForApproval @Tab = 'COMPLETE', @PeriodFrom = @ApproveTabFrom, @PeriodTo = @ApproveTabTo;
IF NOT EXISTS (SELECT 1 FROM @Appr WHERE TimesheetId = @Ts AND IsComplete = 1 AND BillableAmount = 0)
    THROW 59102, N'An approved week with nothing left to bill should be on the Complete tab.', 1;

-- tenant email: SMTP settings verify by test, a billing profile can pick its own invoice template
DECLARE @EtDefault INT, @EtOwn INT;
EXEC admin.usp_TenantEmailSetting_Save @Host = N'smtp.smoke.test', @Port = 587, @Username = N'billing',
     @PasswordSecretRef = N'kv:smoke-smtp', @FromAddress = N'billing@smoke.test', @FromName = N'Smoke Billing';
EXEC admin.usp_TenantEmailSetting_RecordTest @Succeeded = 1;
SELECT @EtDefault = Id FROM admin.fn_EmailTemplateFor(@TenantId, 'INVOICE', @ProfileId);
EXEC admin.usp_EmailTemplate_Save @TemplateId = @EtOwn OUTPUT, @Name = N'Monthly retainer', @Subject = N'{TenantName} invoice {InvoiceNumber}',
     @BodyHtml = N'<p>Hi {ClientName}, {AmountDue} is due {DueDate}.</p>';
UPDATE crm.ClientBillingProfile SET InvoiceEmailTemplateId = @EtOwn WHERE TenantId = @TenantId AND Id = @ProfileId;
IF @EtDefault IS NULL
   OR NOT EXISTS (SELECT 1 FROM admin.EmailTemplate WHERE Id = @EtDefault AND IsDefault = 1)
   OR (SELECT Id FROM admin.fn_EmailTemplateFor(@TenantId, 'INVOICE', @ProfileId)) <> @EtOwn
   OR NOT EXISTS (SELECT 1 FROM admin.TenantEmailSetting WHERE TenantId = @TenantId AND IsVerified = 1)
    THROW 59107, N'Sign-up should seed a default invoice email template, a profile should use its own, and a passed test should verify SMTP.', 1;
EXEC admin.usp_EmailTemplate_Save @TemplateId = @EtOwn, @Delete = 1;
IF (SELECT Id FROM admin.fn_EmailTemplateFor(@TenantId, 'INVOICE', @ProfileId)) <> @EtDefault
    THROW 59108, N'Deleting a profile''s template should fall back to the tenant default.', 1;

-- saved Pilo reports: AI Powered allows 5 per person; the sixth replaces one in the same call
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'AI_POWERED') WHERE Id = @TenantId;
SET @i = 0;
WHILE @i < 5
BEGIN
    SET @SrId = NULL;
    SET @Msg = CONCAT(N'Report ', @i + 1);
    EXEC admin.usp_SavedReport_Save @SavedReportId = @SrId OUTPUT, @Name = @Msg, @Prompt = N'Hours by client last month',
         @Definition = N'{"source":"time","groupBy":["client"]}';
    INSERT INTO @SrIds (Id) VALUES (@SrId);
    SET @i += 1;
END;
SET @SrId = NULL;
SELECT @PsId = Id FROM @SrIds WHERE n = 1;
EXEC admin.usp_SavedReport_Save @SavedReportId = @SrId OUTPUT, @Name = N'Report 6', @Prompt = N'Unbilled hours by project',
     @Definition = N'{"source":"time","groupBy":["project"]}', @ReplaceSavedReportId = @PsId;
EXEC admin.usp_SavedReport_MarkRun @SavedReportId = @SrId;
IF (SELECT COUNT(*) FROM admin.SavedReport WHERE TenantId = @TenantId AND OwnerUserId = @UserId AND IsShared = 0 AND DeletedAt IS NULL) <> 5
   OR NOT EXISTS (SELECT 1 FROM admin.SavedReport WHERE Id = @PsId AND DeletedAt IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM admin.SavedReport WHERE Id = @SrId AND RunCount = 1 AND LastRunAt IS NOT NULL)
    THROW 59103, N'At the 5-report limit, saving with a replacement should swap one report for the new one.', 1;
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'ENTERPRISE') WHERE Id = @TenantId;
EXEC admin.usp_SavedReport_Save @SavedReportId = @SrShared OUTPUT, @Name = N'Company margin', @Prompt = N'Margin by project',
     @Definition = N'{"source":"invoice","groupBy":["project"]}', @IsShared = 1;
SET @PsId = NULL;
EXEC admin.usp_ReportParameterSet_Save @ParameterSetId = @PsId OUTPUT, @ReportCode = 'AR_AGING', @Name = N'Acme only',
     @ParameterJson = N'{"clientId":1}';
EXEC admin.usp_ReportParameterSet_Save @ParameterSetId = @PsId2 OUTPUT, @ReportCode = 'AR_AGING', @Name = N'Acme only',
     @ParameterJson = N'{"clientId":2}';
IF NOT EXISTS (SELECT 1 FROM admin.SavedReport WHERE Id = @SrShared AND IsShared = 1)
   OR @PsId2 <> @PsId OR (SELECT ParameterJson FROM admin.ReportParameterSet WHERE Id = @PsId) <> N'{"clientId":2}'
    THROW 59104, N'Enterprise should allow a company report; saving parameters under the same name should overwrite them.', 1;
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'STANDARD') WHERE Id = @TenantId;

-- custom roles: copy Manager, edit its grid, and a tenant edit to a system role survives the seed
SELECT @PsId = Id FROM sec.Role WHERE TenantId = @TenantId AND Code = 'MANAGER';
EXEC sec.usp_Role_Save @RoleId = @SrRole OUTPUT, @Name = N'Senior consultant', @CopyFromRoleId = @PsId;
EXEC sec.usp_RolePermission_Set @RoleId = @SrRole, @Permissions = N'[{"code":"time.approve","on":false},{"code":"invoice.run","on":true}]';
SELECT @MemberRole = Id FROM sec.Role WHERE TenantId = @TenantId AND Code = 'MEMBER';
EXEC sec.usp_RolePermission_Set @RoleId = @MemberRole, @Permissions = N'[{"code":"expense.submit","on":false}]';
EXEC sec.usp_SeedTenantRoles @TenantId = @TenantId;
IF NOT EXISTS (SELECT 1 FROM sec.Role WHERE Id = @SrRole AND IsSystem = 0 AND BaseRoleCode = 'MANAGER' AND Code LIKE 'CUSTOM[_]%')
   OR EXISTS (SELECT 1 FROM sec.RolePermission WHERE RoleId = @SrRole AND PermissionCode = 'time.approve')
   OR NOT EXISTS (SELECT 1 FROM sec.RolePermission WHERE RoleId = @SrRole AND PermissionCode = 'invoice.run')
   OR NOT EXISTS (SELECT 1 FROM sec.RolePermission WHERE RoleId = @SrRole AND PermissionCode = 'time.enter_others')
   OR EXISTS (SELECT 1 FROM sec.RolePermission WHERE RoleId = @MemberRole AND PermissionCode = 'expense.submit')
   OR NOT EXISTS (SELECT 1 FROM sec.Role WHERE Id = @MemberRole AND BaseRoleCode = 'MEMBER' AND PermissionsCustomizedAt IS NOT NULL)
    THROW 59105, N'A copied role should keep Manager''s permissions with the grid edits, and the seed should not re-grant what a tenant turned off.', 1;
EXEC sec.usp_Role_Save @RoleId = @SrRole, @IsActive = 0;
IF NOT EXISTS (SELECT 1 FROM sec.Role WHERE Id = @SrRole AND IsActive = 0)
    THROW 59106, N'A role nobody has should retire.', 1;
PRINT 'ok 22 approvals tabs, email settings and templates, approved week sent back, approver edits logged, saved Pilo reports with replace, custom roles';

------------------------------------------------------------------ 23. Data-driven permission grid, canned report cards, render type
DECLARE @Grid TABLE (CategoryCode VARCHAR(30), CategoryName NVARCHAR(50), CategoryDescription NVARCHAR(400), CategorySortOrder INT,
        PermissionCode VARCHAR(50), PermissionName NVARCHAR(100), PermissionDescription NVARCHAR(400), SortOrder INT,
        IsGranted BIT, IsFromBaseRole BIT, IsLocked BIT);
DECLARE @Canned TABLE (ReportId INT, Code VARCHAR(40), Name NVARCHAR(100), Description NVARCHAR(400), ReportPath NVARCHAR(400),
        CategoryCode VARCHAR(20), CategoryName NVARCHAR(50), CategorySortOrder INT, SortOrder INT);
DECLARE @MgrRole INT, @OwnerRole INT, @SmokeReport INT, @RtId INT;
SELECT @MgrRole = Id FROM sec.Role WHERE TenantId = @TenantId AND Code = 'MANAGER';
SELECT @OwnerRole = Id FROM sec.Role WHERE TenantId = @TenantId AND Code = 'OWNER';

INSERT INTO @Grid EXEC sec.usp_RolePermission_Grid @RoleId = @MgrRole, @IncludeRole = 0;
IF (SELECT COUNT(*) FROM @Grid) <> (SELECT COUNT(*) FROM sec.Permission WHERE IsActive = 1)
   OR EXISTS (SELECT 1 FROM sec.Permission WHERE CategoryCode IS NULL)
   OR NOT EXISTS (SELECT 1 FROM @Grid WHERE PermissionCode = 'time.approve' AND CategoryCode = 'TIME' AND IsGranted = 1 AND IsFromBaseRole = 1 AND IsLocked = 0)
   OR NOT EXISTS (SELECT 1 FROM @Grid WHERE PermissionCode = 'billing.manage' AND IsGranted = 0 AND IsFromBaseRole = 0)
    THROW 59109, N'The Manager grid should list every active permission under its category, with grants and base-role chips.', 1;
DELETE FROM @Grid;
INSERT INTO @Grid EXEC sec.usp_RolePermission_Grid @RoleId = @OwnerRole, @IncludeRole = 0;
IF EXISTS (SELECT 1 FROM @Grid WHERE IsGranted = 0 OR IsLocked = 0) THROW 59110, N'The Owner grid should be all granted and locked.', 1;

-- a retired permission leaves the grid and stops counting, without losing grants
UPDATE sec.Permission SET IsActive = 0 WHERE Code = 'report.share';
DELETE FROM @Grid;
INSERT INTO @Grid EXEC sec.usp_RolePermission_Grid @RoleId = @MgrRole, @IncludeRole = 0;
IF EXISTS (SELECT 1 FROM @Grid WHERE PermissionCode = 'report.share')
   OR EXISTS (SELECT 1 FROM sec.fn_UserHasPermission(@TenantId, @UserId, 'report.share'))
   OR NOT EXISTS (SELECT 1 FROM sec.RolePermission WHERE TenantId = @TenantId AND RoleId = @MgrRole AND PermissionCode = 'report.share')
    THROW 59111, N'Retiring a permission should hide it and stop it counting, even for the owner, but keep the grants.', 1;
UPDATE sec.Permission SET IsActive = 1 WHERE Code = 'report.share';

-- canned report cards are filtered by permission; the viewer gets USER parameters
INSERT INTO admin.Report (Code, Name, ReportType, ReportPath, Description, CategoryCode, PermissionCode)
VALUES ('SMOKE_AR_AGING', N'AR aging', 'ANALYTIC', N'/Pillar/Smoke_ArAging', N'Open invoices by age.', 'MONEY', 'report.financial');
SET @SmokeReport = SCOPE_IDENTITY();
INSERT INTO admin.ReportParameter (ReportId, Name, DataType, Source, DefaultValue, Label, ListSource, IsRequired, SortOrder)
VALUES (@SmokeReport, 'ClientId', 'INT', 'USER', NULL, N'Client', 'CLIENTS', 0, 10);
INSERT INTO @Canned EXEC admin.usp_Report_ListCanned @IncludeParameters = 0;
IF NOT EXISTS (SELECT 1 FROM @Canned WHERE ReportId = @SmokeReport AND CategoryName = N'Money') THROW 59112, N'The owner should see the canned AR aging card under Money.', 1;
EXEC sp_set_session_context N'UserId', @SubId;   -- a Member: no report.financial
DELETE FROM @Canned;
INSERT INTO @Canned EXEC admin.usp_Report_ListCanned @IncludeParameters = 0;
EXEC sp_set_session_context N'UserId', @UserId;
IF EXISTS (SELECT 1 FROM @Canned WHERE ReportId = @SmokeReport) THROW 59113, N'A Member should not see a report gated by report.financial.', 1;

-- the "Show it as" choice is saved with a Pilo report
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'AI_POWERED') WHERE Id = @TenantId;
EXEC admin.usp_SavedReport_Save @SavedReportId = @RtId OUTPUT, @Name = N'Hours by week', @Prompt = N'Hours by week this quarter',
     @Definition = N'{"source":"time","groupBy":["week"]}', @RenderType = 'BAR', @ReplaceSavedReportId = @SrId;
IF NOT EXISTS (SELECT 1 FROM admin.SavedReport WHERE Id = @RtId AND RenderType = 'BAR')
    THROW 59114, N'A saved Pilo report should keep its chart type.', 1;
UPDATE admin.Tenant SET PlanId = (SELECT Id FROM admin.[Plan] WHERE Code = 'STANDARD') WHERE Id = @TenantId;
PRINT 'ok 23 permission grid from data (categories, base-role chips, owner locked, retired permission), canned cards by permission, render type';

------------------------------------------------------------------ 24. Profile, security, per-page settings permissions, audit log, import, notification channels
DECLARE @Policy TABLE (RequireMfa BIT, MustEnrollMfa BIT, PasswordMinLength INT, PasswordRequireMixed BIT,
        SessionTimeoutMinutes INT, MaxSessionDays INT, IsPlatformAdmin BIT, TenantStatus VARCHAR(15), EmailVerified BIT, MustAcceptTermsId INT);
DECLARE @Audit TABLE (Id BIGINT, OccurredAt DATETIME2(0), ActorUserId INT, ActorName NVARCHAR(201), Area VARCHAR(30),
        EntityType VARCHAR(30), EntityKey NVARCHAR(100), Action VARCHAR(10), Summary NVARCHAR(400), ChangeJson NVARCHAR(MAX), IpAddress VARCHAR(45));
DECLARE @Sessions TABLE (FamilyId UNIQUEIDENTIFIER, StartedAt DATETIME2(0), LastUsedAt DATETIME2(0), ExpiresAt DATETIME2(0),
        UserAgent NVARCHAR(400), IpAddress VARCHAR(45), IsCurrent BIT);
DECLARE @Fam1 UNIQUEIDENTIFIER, @Fam2 UNIQUEIDENTIFIER, @SubFam UNIQUEIDENTIFIER, @Revoked INT, @OldEmail NVARCHAR(254),
        @NewSubEmail NVARCHAR(254) = CONCAT(N'sub.new+', NEWID(), N'@smoke.test'), @ImpJob INT, @ImpJob2 INT,
        @ImpCode NVARCHAR(20) = LEFT(CONCAT(N'IMP', REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'')), 12), @Ch_Count INT,
        @AdminRole INT, @Exp DATETIME2(0) = DATEADD(DAY, 7, SYSUTCDATETIME());
DECLARE @Imports TABLE (RowNumber INT, ErrorText NVARCHAR(1000));
DECLARE @Imported TABLE (RowNumber INT, CreatedEntityId INT, ErrorText NVARCHAR(1000));
EXEC sp_set_session_context N'UserId', @UserId;
EXEC sp_set_session_context N'ClientIp', '203.0.113.7';

-- settings.edit is retired; Admin holds the per-page permissions instead
SELECT @AdminRole = Id FROM sec.Role WHERE TenantId = @TenantId AND Code = 'ADMIN';
IF EXISTS (SELECT 1 FROM sec.Permission WHERE Code = 'settings.edit' AND IsActive = 1)
   OR EXISTS (SELECT 1 FROM sec.RolePermission WHERE TenantId = @TenantId AND PermissionCode = 'settings.edit')
   OR (SELECT COUNT(*) FROM sec.RolePermission WHERE TenantId = @TenantId AND RoleId = @AdminRole AND PermissionCode LIKE 'settings.%') <> 13
   OR NOT EXISTS (SELECT 1 FROM admin.SettingDefinition WHERE SettingKey = 'TimeEntry.RequireApproval' AND PermissionCode = 'settings.time')
    THROW 59115, N'Admin should hold the 13 per-page settings permissions and settings.edit should be retired.', 1;

-- a security setting change is audited; sign-in then asks people without MFA to enroll
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Security.RequireMfa', @Value = N'1';
INSERT INTO @Policy EXEC sec.usp_Auth_SecurityPolicy @AppUserId = @SubId;
INSERT INTO @Audit EXEC admin.usp_AuditLog_List @Area = 'security';
IF NOT EXISTS (SELECT 1 FROM @Policy WHERE RequireMfa = 1 AND MustEnrollMfa = 1 AND PasswordMinLength = 10 AND SessionTimeoutMinutes = 480)
   OR NOT EXISTS (SELECT 1 FROM @Audit WHERE EntityType = 'SETTING' AND EntityKey = N'Security.RequireMfa' AND ActorUserId = @UserId
                  AND IpAddress = '203.0.113.7' AND JSON_VALUE(ChangeJson, '$[0].to') = N'1' AND JSON_VALUE(ChangeJson, '$[0].from') IS NULL)
    THROW 59116, N'Requiring MFA should be audited and make sign-in ask a person without MFA to enroll.', 1;
DELETE FROM @Policy;
INSERT INTO @Policy EXEC sec.usp_Auth_SecurityPolicy @AppUserId = @UserId;      -- the owner set up MFA in step 16
IF NOT EXISTS (SELECT 1 FROM @Policy WHERE RequireMfa = 1 AND MustEnrollMfa = 0) THROW 59117, N'Someone with MFA should not be asked to enroll.', 1;

-- a Member may set their own Pilo writing style
EXEC sp_set_session_context N'UserId', @SubId;
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Pilo.WritingStyle', @Value = N'FORMAL', @AppUserId = @SubId;
EXEC sp_set_session_context N'UserId', @UserId;
IF (SELECT Value FROM admin.fn_Setting(@TenantId, @SubId, 'Pilo.WritingStyle')) <> N'FORMAL'
   OR (SELECT Value FROM admin.fn_Setting(@TenantId, @UserId, 'Pilo.WritingStyle')) <> N'PLAIN'
    THROW 59118, N'A person''s own writing style should apply only to them.', 1;

-- profile, avatar
EXEC sec.usp_UserProfile_Save @Title = N'Principal', @TimeZoneId = N'Eastern Standard Time', @EmailSignatureHtml = N'<p>Smoke Owner</p>';
EXEC sec.usp_UserAvatar_Set @AvatarKind = 'PILO', @PiloEmote = 'WAVE', @PrimaryColor = '#1A73E8', @SecondaryColor = '#FBBC04';
IF NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE Id = @UserId AND Title = N'Principal' AND TimeZoneId = N'Eastern Standard Time'
               AND EmailSignatureHtml = N'<p>Smoke Owner</p>' AND AvatarKind = 'PILO' AND AvatarPiloEmote = 'WAVE' AND AvatarPrimaryColor = '#1A73E8')
    THROW 59119, N'Profile and Pilo avatar should save.', 1;
EXEC sec.usp_UserAvatar_Set @AvatarKind = 'PHOTO', @Photo = 0x89504E470D0A1A0A0000000D49484452;
IF NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE Id = @UserId AND AvatarKind = 'PHOTO')
   OR NOT EXISTS (SELECT 1 FROM sec.UserAvatar WHERE TenantId = @TenantId AND AppUserId = @UserId AND ContentType = 'image/png')
    THROW 59120, N'An uploaded PNG should become the avatar.', 1;

-- sessions: list two devices, sign out the other one
EXEC sec.usp_Auth_IssueRefreshToken @AppUserId = @UserId, @TokenHash = 0x0101010101010101010101010101010101010101010101010101010101010101,
     @ExpiresAt = @Exp, @FamilyId = @Fam1 OUTPUT, @UserAgent = N'Smoke browser';
EXEC sec.usp_Auth_IssueRefreshToken @AppUserId = @UserId, @TokenHash = 0x0202020202020202020202020202020202020202020202020202020202020202,
     @ExpiresAt = @Exp, @FamilyId = @Fam2 OUTPUT, @UserAgent = N'Smoke phone';
INSERT INTO @Sessions EXEC sec.usp_Session_List @CurrentFamilyId = @Fam1;
EXEC sec.usp_Session_Revoke @AllExceptFamilyId = @Fam1, @Count = @Revoked OUTPUT;
IF NOT EXISTS (SELECT 1 FROM @Sessions WHERE FamilyId = @Fam1 AND IsCurrent = 1 AND UserAgent = N'Smoke browser')
   OR NOT EXISTS (SELECT 1 FROM @Sessions WHERE FamilyId = @Fam2 AND IsCurrent = 0)
   OR @Revoked < 1
   OR EXISTS (SELECT 1 FROM sec.RefreshToken WHERE FamilyId = @Fam2 AND RevokedAt IS NULL)
   OR NOT EXISTS (SELECT 1 FROM sec.RefreshToken WHERE FamilyId = @Fam1 AND RevokedAt IS NULL)
    THROW 59121, N'Sessions should list both devices and signing out the others should keep only this one.', 1;

-- an admin changes the Member's email: login email moves, their sessions end, the change is logged
EXEC sec.usp_Auth_IssueRefreshToken @AppUserId = @SubId, @TokenHash = 0x0303030303030303030303030303030303030303030303030303030303030303,
     @ExpiresAt = @Exp, @FamilyId = @SubFam OUTPUT;
EXEC sec.usp_User_ChangeEmail @AppUserId = @SubId, @NewEmail = @NewSubEmail, @OldEmail = @OldEmail OUTPUT;
IF @OldEmail <> @SubEmail
   OR NOT EXISTS (SELECT 1 FROM sec.UserCredential WHERE AppUserId = @SubId AND LoginEmail = LOWER(@NewSubEmail))
   OR EXISTS (SELECT 1 FROM sec.RefreshToken WHERE AppUserId = @SubId AND RevokedAt IS NULL)
   OR NOT EXISTS (SELECT 1 FROM sec.LoginAudit WHERE AppUserId = @SubId AND EventType = 'EMAIL_CHANGED')
   OR NOT EXISTS (SELECT 1 FROM admin.AuditLog WHERE TenantId = @TenantId AND EntityType = 'USER' AND EntityKey = CONVERT(NVARCHAR(100), @SubId)
                  AND JSON_VALUE(ChangeJson, '$[0].to') = @NewSubEmail)
    THROW 59122, N'Changing an email should move the login, end the person''s sessions and be logged twice.', 1;

-- CSV import: one bad client row is skipped, a blank code is generated, contacts attach to the new client
DECLARE @ImpRows NVARCHAR(MAX) = CONCAT(N'[{"clientCode":"', @ImpCode, N'","name":"Imported Co","clientType":"Business","status":"ACTIVE"},',
                                        N'{"name":"No Code LLC"},{"clientCode":"","name":""}]');
EXEC admin.usp_Import_Stage @Kind = 'CLIENTS', @Rows = @ImpRows, @FileName = N'clients.csv', @JobId = @ImpJob OUTPUT;
INSERT INTO @Imports EXEC admin.usp_Import_Validate @JobId = @ImpJob;
INSERT INTO @Imported EXEC admin.usp_Import_Commit @JobId = @ImpJob;
IF NOT EXISTS (SELECT 1 FROM @Imports WHERE RowNumber = 4 AND ErrorText LIKE N'Name is required%') OR (SELECT COUNT(*) FROM @Imports) <> 1
   OR NOT EXISTS (SELECT 1 FROM admin.ImportJob WHERE Id = @ImpJob AND Status = 'IMPORTED' AND ErrorCount = 1 AND ImportedCount = 2)
   OR NOT EXISTS (SELECT 1 FROM crm.Client WHERE TenantId = @TenantId AND ClientCode = @ImpCode AND Name = N'Imported Co')
   OR NOT EXISTS (SELECT 1 FROM crm.Client AS c JOIN @Imported AS i ON i.CreatedEntityId = c.Id
                  WHERE i.RowNumber = 3 AND c.Name = N'No Code LLC' AND c.ClientCode LIKE N'C[0-9]%')
   OR NOT EXISTS (SELECT 1 FROM crm.ClientBillingProfile AS p JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
                  WHERE c.TenantId = @TenantId AND c.ClientCode = @ImpCode)
    THROW 59123, N'The client import should skip the row without a name, generate a code and give new clients a billing profile.', 1;
SET @ImpRows = CONCAT(N'[{"clientCode":"', @ImpCode, N'","firstName":"Ada","lastName":"Lovelace","email":"ada@imported.test","isPrimary":"yes"},',
                      N'{"clientCode":"', @ImpCode, N'","firstName":"Grace","email":"grace@imported.test"}]');
EXEC admin.usp_Import_Stage @Kind = 'CONTACTS', @Rows = @ImpRows, @JobId = @ImpJob2 OUTPUT;
DELETE FROM @Imports;
DELETE FROM @Imported;
INSERT INTO @Imports EXEC admin.usp_Import_Validate @JobId = @ImpJob2;
INSERT INTO @Imported EXEC admin.usp_Import_Commit @JobId = @ImpJob2;
IF EXISTS (SELECT 1 FROM @Imports)
   OR (SELECT COUNT(*) FROM crm.Contact AS k JOIN crm.Client AS c ON c.TenantId = k.TenantId AND c.Id = k.ClientId
       WHERE c.TenantId = @TenantId AND c.ClientCode = @ImpCode) <> 2
   OR NOT EXISTS (SELECT 1 FROM crm.Contact AS k JOIN crm.Client AS c ON c.TenantId = k.TenantId AND c.Id = k.ClientId
                  WHERE c.ClientCode = @ImpCode AND k.FirstName = N'Ada' AND k.IsPrimary = 1)
    THROW 59124, N'Both contacts should import onto the new client, Ada as primary.', 1;

-- notification channels: a company lock, an email-only choice, new types, dismiss all
EXEC admin.usp_TenantNotificationDefault_Set @Defaults = N'[{"type":"TIMESHEET_DUE","channel":"IN_APP","on":true,"locked":true},{"type":"INVOICE_PAID","channel":"EMAIL","on":true}]';
EXEC sec.usp_NotificationSetting_Set @Settings = N'{"MENTIONED": {"inApp": false, "email": true}}';
IF NOT EXISTS (SELECT 1 FROM sec.fn_NotificationChannels(@TenantId, @UserId, 'TIMESHEET_DUE') WHERE InAppOn = 1 AND InAppLocked = 1)
   OR NOT EXISTS (SELECT 1 FROM sec.fn_NotificationChannels(@TenantId, @UserId, 'INVOICE_PAID') WHERE EmailOn = 1 AND InAppOn = 0)
   OR NOT EXISTS (SELECT 1 FROM sec.fn_NotificationChannels(@TenantId, @UserId, 'MENTIONED') WHERE InAppOn = 0 AND EmailOn = 1)
    THROW 59125, N'Company defaults, locks and a person''s email-only choice should resolve per channel.', 1;
DECLARE @Me NVARCHAR(20) = CONCAT(N'[', @UserId, N']');
EXEC sp_set_session_context N'UserId', @SubId;
EXEC sec.usp_Notification_Raise @NotificationType = 'MENTIONED', @EntityType = 'TASK', @EntityId = @NtTaskId,
     @Title = N'Sam mentioned you', @RecipientUserIds = @Me;
EXEC sec.usp_Notification_Raise @NotificationType = 'TIMESHEET_DUE', @EntityType = 'TIMESHEET', @EntityId = @Ts,
     @Title = N'Submit your week';
EXEC sec.usp_Notification_Raise @NotificationType = 'PLAN_PAYMENT_FAILED', @EntityType = 'STATEMENT', @EntityId = 1,
     @Title = N'Your card was declined', @Count = @Ch_Count OUTPUT;
EXEC sp_set_session_context N'UserId', @UserId;
IF NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @UserId AND NotificationType = 'MENTIONED' AND EntityId = @NtTaskId
               AND SendEmail = 1 AND DismissedAt IS NOT NULL AND EmailedAt IS NULL)
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @UserId AND NotificationType = 'TIMESHEET_DUE' AND DismissedAt IS NULL)
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @UserId AND NotificationType = 'PLAN_PAYMENT_FAILED' AND DismissedAt IS NULL)
   OR EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'PLAN_PAYMENT_FAILED')
    THROW 59126, N'An email-only mention should skip the bell, the week reminder should reach its owner and the payment failure only billing managers.', 1;
EXEC sec.usp_Notification_Dismiss @All = 1;
IF EXISTS (SELECT 1 FROM sec.Notification WHERE TenantId = @TenantId AND AppUserId = @UserId AND DismissedAt IS NULL)
    THROW 59127, N'Dismiss all should clear the bell.', 1;
EXEC sp_set_session_context N'ClientIp', NULL;
PRINT 'ok 24 settings permissions per page, MFA policy, audit log, profile and avatar, sessions, email change, CSV import, notification channels';

------------------------------------------------------------------ 25. Seats, plan changes, statement lines, back office, support, sample company
DECLARE @Seat3 BINARY(32) = HASHBYTES('SHA2_256', CONCAT('seat3', NEWID())), @Seat3Id INT,
        @Seat3Email NVARCHAR(254) = CONCAT(N'tess+', NEWID(), N'@smoke.test'),
        @FlatId INT = (SELECT Id FROM admin.[Plan] WHERE Code = 'STANDARD'),
        @PcId INT, @PcApplied BIT, @NextMonth DATE = DATEADD(MONTH, 1, @ThisMonth), @Days INT, @NextSt INT, @Due DECIMAL(19,2),
        @GrantId INT, @ImpId INT, @AsId INT, @TicketId INT, @AnnId INT, @ArtId INT, @Gen BIGINT;
SET @Days = DAY(EOMONTH(@NextMonth));

-- seats: Flat includes 2 (the owner and Sam); a third login is an extra seat, which the owner (billing.manage) may add
IF NOT EXISTS (SELECT 1 FROM admin.fn_TenantSeats(@TenantId) WHERE UsedSeats = 2 AND IncludedSeats = 2 AND ExtraSeats = 0)
    THROW 59132, N'Flat should include two seats, both in use.', 1;
EXEC sec.usp_User_Invite @Email = @Seat3Email, @TokenHash = @Seat3, @FirstName = N'Tess', @LastName = N'Third', @AppUserId = @Seat3Id OUTPUT;
IF NOT EXISTS (SELECT 1 FROM admin.fn_TenantSeats(@TenantId) WHERE UsedSeats = 3 AND ExtraSeats = 1 AND ExtraSeatsMonthly = 12.00)
   OR NOT EXISTS (SELECT 1 FROM admin.TenantSeatDaily WHERE TenantId = @TenantId AND SeatDate = CAST(SYSUTCDATETIME() AS DATE)
                  AND PeakSeats = 3 AND EndSeats = 3)
    THROW 59133, N'A third login should be one extra seat at 12.00 and be counted in today''s seats.', 1;

-- plan: upgrade now; a downgrade to Flat is blocked by the saved Pilo reports from steps 22-23 and warns about the extra seat;
-- with the reports gone it waits for the 1st, then is cancelled
EXEC admin.usp_PlanChange_Request @ToPlanCode = 'AI_POWERED', @PlanChangeId = @PcId OUTPUT, @Applied = @PcApplied OUTPUT;
IF @PcApplied <> 1
   OR NOT EXISTS (SELECT 1 FROM admin.Tenant AS t JOIN admin.[Plan] AS p ON p.Id = t.PlanId WHERE t.Id = @TenantId AND p.Code = 'AI_POWERED')
   OR NOT EXISTS (SELECT 1 FROM admin.TenantPlanChange WHERE Id = @PcId AND Kind = 'UPGRADE' AND Status = 'APPLIED'
                  AND EffectiveDate = CAST(SYSUTCDATETIME() AS DATE))
    THROW 59134, N'An upgrade should apply at once and be recorded.', 1;
IF NOT EXISTS (SELECT 1 FROM admin.fn_PlanChangeIssues(@TenantId, @FlatId) WHERE IssueCode = 'SAVED_REPORTS' AND Severity = 'BLOCK' AND AppUserId = @UserId)
   OR NOT EXISTS (SELECT 1 FROM admin.fn_PlanChangeIssues(@TenantId, @FlatId) WHERE IssueCode = 'COMPANY_REPORTS' AND Severity = 'BLOCK')
   OR NOT EXISTS (SELECT 1 FROM admin.fn_PlanChangeIssues(@TenantId, @FlatId) WHERE IssueCode = 'SEATS' AND Severity = 'WARN' AND CurrentCount = 3)
    THROW 59135, N'Downgrading to Flat should list the saved reports to remove and warn about the extra seat.', 1;
UPDATE admin.SavedReport SET DeletedAt = SYSUTCDATETIME() WHERE TenantId = @TenantId AND DeletedAt IS NULL;
EXEC admin.usp_PlanChange_Request @ToPlanCode = 'STANDARD', @PlanChangeId = @PcId OUTPUT, @Applied = @PcApplied OUTPUT;
IF @PcApplied <> 0
   OR NOT EXISTS (SELECT 1 FROM admin.TenantPlanChange WHERE Id = @PcId AND Kind = 'DOWNGRADE' AND Status = 'PENDING' AND EffectiveDate = @NextMonth)
   OR NOT EXISTS (SELECT 1 FROM admin.Tenant AS t JOIN admin.[Plan] AS p ON p.Id = t.PlanId WHERE t.Id = @TenantId AND p.Code = 'AI_POWERED')
    THROW 59136, N'A downgrade should wait for the 1st of next month.', 1;
EXEC admin.usp_PlanChange_Cancel;
IF NOT EXISTS (SELECT 1 FROM admin.TenantPlanChange WHERE Id = @PcId AND Status = 'CANCELLED')
    THROW 59136, N'Cancelling should drop the waiting downgrade.', 1;

-- Pilo: three reports this month against an allowance Pillar set to 2 (custom quote), plus 2 included seats
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC admin.usp_Tenant_SetOverride @TenantId = @TenantId, @SettingKey = 'Seats.IncludedOverride', @Value = N'2', @Reason = N'Smoke test quote';
EXEC admin.usp_Tenant_SetOverride @TenantId = @TenantId, @SettingKey = 'Pilo.MonthlyReportsOverride', @Value = N'2', @Reason = N'Smoke test quote';
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
SET @i = 0;
WHILE @i < 3
BEGIN
    EXEC ai.usp_Generation_Log @Feature = 'ASK_REPORT', @Model = 'smoke-model', @InputTokens = 1200, @OutputTokens = 400,
         @CostUsd = 0.012, @CountsTowardQuota = 1, @GenerationId = @Gen OUTPUT;
    SET @i += 1;
END;
IF NOT EXISTS (SELECT 1 FROM admin.fn_PiloUsage(@TenantId, @ThisMonth) WHERE Reports = 3 AND IncludedReports = 2 AND OverageReports = 1 AND OverageAmount = 0.75)
   OR (SELECT COUNT(*) FROM admin.PlatformAudit WHERE TenantId = @TenantId AND Action = 'SET_OVERRIDE' AND Reason IS NOT NULL) <> 2
    THROW 59137, N'Three reports on a 2-report allowance should be one overage report at 0.75, and the overrides logged with their reason.', 1;

-- next month's statement: AI Powered until the 15th, then Enterprise (prorated by day), one extra seat at the peak, one Pilo
-- report over (the reports are moved into next month for this)
UPDATE ai.Generation SET CreatedAt = DATEADD(MONTH, 1, CreatedAt) WHERE TenantId = @TenantId;
INSERT INTO admin.TenantPlanChange (TenantId, FromPlanId, ToPlanId, Kind, Status, EffectiveDate, AppliedAt)
SELECT @TenantId, a.Id, e.Id, 'PLATFORM', 'APPLIED', DATEADD(DAY, 14, @NextMonth), SYSUTCDATETIME()
FROM admin.[Plan] AS a CROSS JOIN admin.[Plan] AS e WHERE a.Code = 'AI_POWERED' AND e.Code = 'ENTERPRISE';
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC admin.usp_PlatformStatement_Generate @PeriodStart = @NextMonth, @TenantId = @TenantId;
SELECT @NextSt = Id, @Due = AmountDue FROM admin.PlatformStatement WHERE TenantId = @TenantId AND PeriodStart = @NextMonth AND Status <> 'VOID';
IF @NextSt IS NULL
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformStatementLine WHERE StatementId = @NextSt AND LineType = 'PLAN' AND Quantity = 14
                  AND Amount = ROUND(CONVERT(DECIMAL(19,2), 39) * 14 / @Days, 2))
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformStatementLine WHERE StatementId = @NextSt AND LineType = 'PLAN' AND Quantity = @Days - 14
                  AND Amount = ROUND(CONVERT(DECIMAL(19,2), 209) * (@Days - 14) / @Days, 2))
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformStatementLine WHERE StatementId = @NextSt AND LineType = 'SEATS' AND Quantity = 1 AND Amount = 12.00)
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformStatementLine WHERE StatementId = @NextSt AND LineType = 'PILO' AND Quantity = 1 AND Amount = 0.35)
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformStatement AS s
                  WHERE s.Id = @NextSt
                    AND s.SubscriptionTotal = (SELECT SUM(Amount) FROM admin.PlatformStatementLine AS l
                                               WHERE l.StatementId = s.Id AND l.LineType IN ('PLAN', 'SEATS', 'PILO'))
                    AND s.AmountDue = s.FeeTotal + s.MinimumAdjustment + s.SubscriptionTotal + s.CreditApplied)
    THROW 59138, N'The statement should prorate both plans, bill one extra seat at 12.00 and one Pilo report at 0.35, and add them up.', 1;

-- the charge fails (retry tomorrow, Pillar's inbox), then Pillar marks it paid by check
EXEC admin.usp_PlatformStatement_RecordPayment @StatementId = @NextSt, @Amount = @Due, @Succeeded = 0,
     @PaymentMethodId = @CardId, @FailureReason = N'insufficient_funds';
IF NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WHERE Id = @NextSt AND Status = 'PAST_DUE' AND NextRetryAt > SYSUTCDATETIME())
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformNotification WHERE TenantId = @TenantId AND Kind = 'PAYMENT_FAILED' AND EntityId = @NextSt)
    THROW 59139, N'A failed charge should set the next retry and reach Pillar''s inbox.', 1;
EXEC admin.usp_PlatformFailedCharges;
EXEC admin.usp_PlatformStatement_MarkPaid @StatementId = @NextSt, @Reason = N'Paid by check 1001';
IF NOT EXISTS (SELECT 1 FROM admin.PlatformStatement WHERE Id = @NextSt AND Status = 'PAID' AND NextRetryAt IS NULL)
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformPayment WHERE StatementId = @NextSt AND Succeeded = 1 AND Note = N'Paid by check 1001')
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformAudit WHERE TenantId = @TenantId AND Action = 'MARK_PAID')
    THROW 59139, N'Mark paid should settle the statement with the reason on the payment and in Pillar''s audit trail.', 1;

-- back office reads (their grids show in SSMS), then suspend and reinstate
EXEC admin.usp_PlatformDashboard @IncludeTrend = 1;
EXEC admin.usp_PlatformTenant_List @Search = N'Smoke Test';
EXEC admin.usp_PlatformTenant_Get @TenantId = @TenantId;
EXEC admin.usp_PlatformPiloCost @Month = @NextMonth;
EXEC admin.usp_Tenant_SetStatus @TenantId = @TenantId, @Status = 'SUSPENDED', @Reason = N'Smoke test';
IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId AND Status = 'SUSPENDED')
   OR EXISTS (SELECT 1 FROM sec.RefreshToken AS r JOIN sec.UserCredential AS c ON c.AppUserId = r.AppUserId
              WHERE c.TenantId = @TenantId AND r.RevokedAt IS NULL)
    THROW 59140, N'Suspending should sign everyone out.', 1;
EXEC admin.usp_Tenant_SetStatus @TenantId = @TenantId, @Status = 'ACTIVE', @Reason = N'Smoke test';
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
IF NOT EXISTS (SELECT 1 FROM admin.Tenant WHERE Id = @TenantId AND Status = 'ACTIVE')
   OR NOT EXISTS (SELECT 1 FROM admin.AuditLog WHERE TenantId = @TenantId AND EntityType = 'TENANT' AND Action = 'DISABLE')
    THROW 59140, N'Reinstating should make the tenant ACTIVE, and the tenant''s audit log should show the suspension.', 1;

-- support access: the owner allows it, Pillar signs in as the owner, a change made then is tagged, revoking ends the session
EXEC sec.usp_SupportAccess_Grant @Days = 3, @Note = N'Smoke ticket', @GrantId = @GrantId OUTPUT;
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC sec.usp_Impersonation_Start @TenantId = @TenantId, @Reason = N'Smoke test: check a setting', @AsUserId = @AsId OUTPUT,
     @ImpersonationSessionId = @ImpId OUTPUT;
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
EXEC sp_set_session_context N'ImpersonationSessionId', @ImpId;
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Billing.StatementEmail', @Value = N'billing@smoke.test';
CREATE TABLE #Imp (IsActive BIT);
INSERT INTO #Imp EXEC sec.usp_Impersonation_Check @ImpersonationSessionId = @ImpId;
EXEC sp_set_session_context N'ImpersonationSessionId', NULL;
EXEC sec.usp_SupportAccess_Revoke;
INSERT INTO #Imp EXEC sec.usp_Impersonation_Check @ImpersonationSessionId = @ImpId;
IF @AsId <> @UserId
   OR (SELECT COUNT(*) FROM #Imp WHERE IsActive = 1) <> 1 OR (SELECT COUNT(*) FROM #Imp WHERE IsActive = 0) <> 1
   OR NOT EXISTS (SELECT 1 FROM admin.AuditLog WHERE TenantId = @TenantId AND ImpersonationSessionId = @ImpId AND EntityKey = N'Billing.StatementEmail')
   OR NOT EXISTS (SELECT 1 FROM admin.AuditLog WHERE TenantId = @TenantId AND Area = 'support' AND EntityType = 'SUPPORT_SESSION')
   OR NOT EXISTS (SELECT 1 FROM sec.ImpersonationSession WHERE Id = @ImpId AND EndReason = 'REVOKED')
   OR NOT EXISTS (SELECT 1 FROM sec.LoginAudit WHERE TenantId = @TenantId AND EventType = 'SUPPORT_SIGNIN')
    THROW 59141, N'Support sign-in should need the tenant''s grant, tag changes made during it, and end when the grant is revoked.', 1;
DROP TABLE #Imp;

-- support ticket: Sam asks, Pillar adds an internal note and replies, Sam answers
EXEC sp_set_session_context N'UserId', @SubId;
EXEC support.usp_Ticket_Open @TicketType = 'QUESTION', @Subject = N'How do I export time?', @Body = N'Looking for a CSV.', @TicketId = @TicketId OUTPUT;
EXEC sp_set_session_context N'UserId', @UserId;
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC support.usp_Ticket_Reply @TicketId = @TicketId, @Body = N'Customer is on Flat.', @IsInternal = 1;
EXEC support.usp_Ticket_Reply @TicketId = @TicketId, @Body = N'Reports > Time > Export.';
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
IF NOT EXISTS (SELECT 1 FROM support.Ticket WHERE Id = @TicketId AND Status = 'PENDING' AND LastMessageFromPillar = 1)
   OR NOT EXISTS (SELECT 1 FROM sec.Notification WHERE AppUserId = @SubId AND NotificationType = 'SUPPORT_REPLY' AND EntityId = @TicketId)
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformNotification WHERE TenantId = @TenantId AND Kind = 'SUPPORT_TICKET' AND EntityId = @TicketId)
    THROW 59142, N'Pillar''s reply should wait on the customer and notify Sam; the new ticket should reach Pillar''s inbox.', 1;
EXEC sp_set_session_context N'UserId', @SubId;
EXEC support.usp_Ticket_Reply @TicketId = @TicketId, @Body = N'Found it, thanks.';
EXEC support.usp_Ticket_SetStatus @TicketId = @TicketId, @Status = 'CLOSED';
EXEC sp_set_session_context N'UserId', @UserId;
IF NOT EXISTS (SELECT 1 FROM support.Ticket WHERE Id = @TicketId AND Status = 'CLOSED')
   OR (SELECT COUNT(*) FROM support.TicketMessage WHERE TicketId = @TicketId) <> 4
   OR NOT EXISTS (SELECT 1 FROM admin.PlatformNotification WHERE TenantId = @TenantId AND Kind = 'SUPPORT_REPLY' AND EntityId = @TicketId)
    THROW 59142, N'Sam''s answer should reach Pillar, and Sam may close the ticket.', 1;

-- announcements and help articles
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC admin.usp_Announcement_Save @Title = N'Smoke maintenance', @Severity = 'MAINTENANCE', @AnnouncementId = @AnnId OUTPUT;
EXEC help.usp_Article_Save @Slug = 'smoke-test-article', @Title = N'Smoke test', @Body = N'# Hello', @Category = N'Getting started',
     @IsPublished = 1, @ArticleId = @ArtId OUTPUT;
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
EXEC sec.usp_Announcement_Dismiss @AnnouncementId = @AnnId;
IF NOT EXISTS (SELECT 1 FROM sec.UserAnnouncementDismissal WHERE AppUserId = @UserId AND AnnouncementId = @AnnId)
   OR NOT EXISTS (SELECT 1 FROM help.Article WHERE Id = @ArtId AND IsPublished = 1 AND PublishedAt IS NOT NULL)
    THROW 59143, N'An announcement should be dismissable and a published article saved.', 1;

-- sample company: load it, then remove it again
CREATE TABLE #Sample (n INT);
INSERT INTO #Sample EXEC admin.usp_SampleData_Load;
IF NOT EXISTS (SELECT 1 FROM #Sample WHERE n = 2)
   OR (SELECT COUNT(*) FROM crm.ClientProject AS p JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId
       WHERE c.TenantId = @TenantId AND c.IsSample = 1) <> 2
   OR (SELECT COUNT(*) FROM crm.ClientTask AS t JOIN crm.ClientProject AS p ON p.TenantId = t.TenantId AND p.Id = t.ProjectId
       JOIN crm.Client AS c ON c.TenantId = p.TenantId AND c.Id = p.ClientId WHERE c.TenantId = @TenantId AND c.IsSample = 1) <> 4
    THROW 59144, N'The sample company should load two clients, two projects and four tasks.', 1;
INSERT INTO #Sample EXEC admin.usp_SampleData_Remove;
IF EXISTS (SELECT 1 FROM crm.Client WHERE TenantId = @TenantId AND IsSample = 1)
   OR EXISTS (SELECT 1 FROM crm.ClientProject WHERE TenantId = @TenantId AND ProjectCode LIKE N'SAMPLE-%')
    THROW 59144, N'Removing the sample company should delete its clients and projects.', 1;
DROP TABLE #Sample;
PRINT 'ok 25 seats, plan changes, prorated plan/seat/Pilo statement lines, failed charge and mark paid, suspend, support sign-in, tickets, announcements, help, sample company';

------------------------------------------------------------------ 26. Today layouts, weekly hours goal, weekly expenses with receipt reading, search, contacts
DECLARE @OwnerRoleId INT;
DECLARE @Layout TABLE (LayoutJson NVARCHAR(MAX), Source VARCHAR(10), RoleId INT, RoleName NVARCHAR(50),
        BaseRoleCode VARCHAR(20), RoleLayoutJson NVARCHAR(MAX), RoleLayoutPublishedAt DATETIME2(0));
DECLARE @Hours TABLE (AppUserId INT, DisplayName NVARCHAR(201), WeekStart DATE, WeekEnd DATE, TimesheetId INT, TimesheetStatus VARCHAR(30),
        LoggedHours DECIMAL(9,2), BillableHours DECIMAL(9,2), GoalHours DECIMAL(9,2), PercentOfGoal DECIMAL(9,1));
DECLARE @ExDay DATE = DATEADD(DAY, -56, @WorkDate), @ExCat INT, @ExLine1 INT, @ExLine2 INT, @ExBill INT, @ExBill2 INT, @ExSheet INT,
        @ReceiptGen BIGINT, @ExNextDay DATE;
DECLARE @Found TABLE (ResultType VARCHAR(20), EntityId INT, PublicId UNIQUEIDENTIFIER, ParentPublicId UNIQUEIDENTIFIER, Title NVARCHAR(400),
        Subtitle NVARCHAR(400), Snippet NVARCHAR(400), Rank INT, ItemDate DATETIME2(0));
DECLARE @Contacts TABLE (ContactId INT, PublicId UNIQUEIDENTIFIER, FirstName NVARCHAR(100), LastName NVARCHAR(100), DisplayName NVARCHAR(201),
        Title NVARCHAR(100), Email NVARCHAR(254), Phone NVARCHAR(30), Mobile NVARCHAR(30), ContactRoleId INT, ContactRoleName NVARCHAR(100),
        IsPrimary BIT, IsActive BIT, ClientId INT, ClientPublicId UNIQUEIDENTIFIER, ClientCode NVARCHAR(20), ClientName NVARCHAR(200),
        CreatedAt DATETIME2(0), ModifiedAt DATETIME2(0), TotalCount INT);

-- Today: Pillar's default, then the role's published layout, then the person's own, then reset back to the role's
SELECT @OwnerRoleId = RoleId FROM sec.AppUser WHERE Id = @UserId;
INSERT INTO @Layout EXEC admin.usp_TodayLayout_Get;
EXEC admin.usp_RoleDashboardLayout_Publish @RoleId = @OwnerRoleId, @LayoutJson = N'{"widgets":["approvals","unbilled","owed","budgets"]}';
INSERT INTO @Layout EXEC admin.usp_TodayLayout_Get;
EXEC admin.usp_UserPreference_Set @PrefKey = 'ui.todayLayout', @Value = N'{"widgets":["timer","today"]}';
INSERT INTO @Layout EXEC admin.usp_TodayLayout_Get;
EXEC admin.usp_TodayLayout_Reset;
INSERT INTO @Layout EXEC admin.usp_TodayLayout_Get;
EXEC admin.usp_RoleDashboardLayout_List;
IF (SELECT COUNT(*) FROM @Layout WHERE Source = 'DEFAULT' AND LayoutJson IS NULL AND BaseRoleCode = 'OWNER') <> 1
   OR (SELECT COUNT(*) FROM @Layout WHERE Source = 'ROLE' AND LayoutJson LIKE N'%approvals%') <> 2
   OR (SELECT COUNT(*) FROM @Layout WHERE Source = 'USER' AND LayoutJson LIKE N'%timer%' AND RoleLayoutJson LIKE N'%approvals%') <> 1
   OR NOT EXISTS (SELECT 1 FROM admin.AuditLog WHERE TenantId = @TenantId AND EntityType = 'TODAY_LAYOUT' AND Action = 'UPDATE')
    THROW 59145, N'Today should use the person''s layout, else the role''s published one, else Pillar''s default; reset drops the person''s own.', 1;

-- weekly hours goal: tenant 40, the owner's own 30
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Time.WeeklyHoursGoal', @Value = N'30', @AppUserId = @UserId;
INSERT INTO @Hours EXEC crm.usp_WeeklyHours_Get @WeekOf = @WorkDate, @AllUsers = 1;
IF NOT EXISTS (SELECT 1 FROM @Hours WHERE AppUserId = @UserId AND GoalHours = 30 AND LoggedHours >= 1.5 AND WeekStart <= @WorkDate AND WeekEnd >= @WorkDate)
   OR NOT EXISTS (SELECT 1 FROM admin.fn_Setting(@TenantId, NULL, 'Time.WeeklyHoursGoal') WHERE Value = N'40')
    THROW 59146, N'Weekly hours should show the week''s logged time against the person''s own goal, or the tenant''s.', 1;

-- weekly expenses: approvals on, expense reports on (Pillar sets the feature)
EXEC sp_set_session_context N'IsPlatformAdmin', 1;
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'Feature.ExpenseReports', @Value = N'1';
EXEC sp_set_session_context N'IsPlatformAdmin', NULL;
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'AP.RequireApproval', @Value = N'1';
EXEC admin.usp_Setting_Set @TenantId = @TenantId, @SettingKey = 'TimeEntry.RequireApproval', @Value = N'1';
SELECT TOP (1) @ExCat = Id FROM lkp.ExpenseCategory WHERE TenantId = @TenantId AND IsActive = 1 AND UnitRate IS NULL ORDER BY SortOrder;

-- a receipt read by Pilo doesn't count toward the report allowance, even when the API says it does
EXEC ai.usp_Generation_Log @Feature = 'RECEIPT', @Model = 'smoke-vision', @InputTokens = 900, @OutputTokens = 80, @CostUsd = 0.004,
     @CountsTowardQuota = 1, @GenerationId = @ReceiptGen OUTPUT;
IF NOT EXISTS (SELECT 1 FROM ai.Generation WHERE Id = @ReceiptGen AND Feature = 'RECEIPT' AND CountsTowardQuota = 0)
    THROW 59147, N'A receipt read should be logged without counting toward the Pilo allowance.', 1;

EXEC ap.usp_Expense_Save @BillLineId = @ExLine1 OUTPUT, @ExpenseDate = @ExDay, @ExpenseCategoryId = @ExCat, @Description = N'Printer paper',
     @Amount = 42.18, @Merchant = N'Office Depot', @ReceiptGenerationId = @ReceiptGen,
     @ReceiptReadJson = N'{"amount":{"value":42.18,"confidence":0.97},"category":{"value":"SUPPLIES","confidence":0.62}}',
     @ReceiptConfidence = 0.62, @BillId = @ExBill OUTPUT;
EXEC ap.usp_Expense_Save @BillLineId = @ExLine2 OUTPUT, @ExpenseDate = @ExDay, @ExpenseCategoryId = @ExCat, @Description = N'Parking',
     @Amount = 7.00, @BillId = @ExBill2 OUTPUT;
SELECT @ExSheet = TimesheetId FROM ap.Bill WHERE Id = @ExBill;
IF @ExBill2 <> @ExBill OR @ExSheet IS NULL
   OR NOT EXISTS (SELECT 1 FROM ap.Bill AS b JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
                  JOIN crm.Timesheet AS t ON t.Id = b.TimesheetId
                  WHERE b.Id = @ExBill AND s.SystemCode = 'DRAFT' AND b.Total = 49.18 AND b.PayeeUserId = @UserId
                    AND t.AppUserId = @UserId AND t.WeekStart <= @ExDay AND t.WeekEnd >= @ExDay AND b.BillDate = t.WeekEnd)
   OR NOT EXISTS (SELECT 1 FROM ap.BillLine WHERE Id = @ExLine1 AND Merchant = N'Office Depot' AND ReceiptConfidence = 0.62
                  AND ReceiptGenerationId = @ReceiptGen)
    THROW 59148, N'The week''s first expense should start one draft report for that timesheet week, with what Pilo read on the line.', 1;

-- the week goes in with only expenses on it, is sent back, and the expenses go back with it
EXEC crm.usp_Timesheet_Submit @TimesheetId = @ExSheet;
IF NOT EXISTS (SELECT 1 FROM ap.Bill AS b JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
               WHERE b.Id = @ExBill AND s.SystemCode = 'SUBMITTED' AND b.SubmittedAt IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId
                  WHERE t.Id = @ExSheet AND s.SystemCode = 'SUBMITTED')
    THROW 59149, N'Submitting the week should submit its expense report and show the week as submitted.', 1;
EXEC ap.usp_Expense_List @WeekOf = @ExDay;
EXEC crm.usp_Timesheet_Reject @TimesheetId = @ExSheet, @Reason = N'Add the parking receipt';
IF NOT EXISTS (SELECT 1 FROM ap.Bill AS b JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
               WHERE b.Id = @ExBill AND s.SystemCode = 'DRAFT' AND b.RejectedReason = N'Add the parking receipt')
   OR NOT EXISTS (SELECT 1 FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId
                  WHERE t.Id = @ExSheet AND s.SystemCode = 'REJECTED')
    THROW 59150, N'Sending the week back should send its expenses back with the reason.', 1;

-- moving an expense to the next week moves it to that week's report; deleting it leaves that report empty
SET @ExNextDay = DATEADD(DAY, 7, @ExDay);
EXEC ap.usp_Expense_Save @BillLineId = @ExLine2 OUTPUT, @ExpenseDate = @ExNextDay, @ExpenseCategoryId = @ExCat, @Description = N'Parking',
     @Amount = 7.00, @BillId = @ExBill2 OUTPUT;
IF @ExBill2 = @ExBill
   OR NOT EXISTS (SELECT 1 FROM ap.Bill WHERE Id = @ExBill AND Total = 42.18)
   OR NOT EXISTS (SELECT 1 FROM ap.Bill WHERE Id = @ExBill2 AND Total = 7.00 AND TimesheetId <> @ExSheet)
    THROW 59151, N'Changing an expense''s date to another week should move it to that week''s report.', 1;
EXEC ap.usp_Expense_Save @BillLineId = @ExLine2 OUTPUT, @Delete = 1, @BillId = @ExBill2 OUTPUT;
IF EXISTS (SELECT 1 FROM ap.BillLine WHERE BillId = @ExBill2) OR NOT EXISTS (SELECT 1 FROM ap.Bill WHERE Id = @ExBill2 AND Total = 0)
    THROW 59151, N'Deleting an expense should remove its line and total.', 1;

-- resubmitted and approved together: the report opens for payment
EXEC crm.usp_Timesheet_Submit @TimesheetId = @ExSheet;
EXEC crm.usp_Timesheet_Approve @TimesheetId = @ExSheet;
IF NOT EXISTS (SELECT 1 FROM ap.Bill AS b JOIN lkp.BillStatus AS s ON s.TenantId = b.TenantId AND s.Id = b.BillStatusId
               WHERE b.Id = @ExBill AND s.SystemCode = 'OPEN' AND b.ApprovedBy = @UserId AND b.RejectedAt IS NULL)
   OR NOT EXISTS (SELECT 1 FROM crm.Timesheet AS t JOIN lkp.TimesheetStatus AS s ON s.TenantId = t.TenantId AND s.Id = t.TimesheetStatusId
                  WHERE t.Id = @ExSheet AND s.SystemCode = 'APPROVED')
    THROW 59152, N'Approving the week should approve its expenses too.', 1;

-- search: a client by name, the task by its key (exact first), and text inside a task comment
INSERT INTO crm.TaskComment (TenantId, TaskId, Body) VALUES (@TenantId, @TaskId, N'<p>Ask about the zebrafish migration</p>');
INSERT INTO @Found EXEC crm.usp_Search @Query = N'SMOKE', @Types = 'CLIENT';
INSERT INTO @Found EXEC crm.usp_Search @Query = @TaskKey;
INSERT INTO @Found EXEC crm.usp_Search @Query = N'zebrafish', @Types = 'task_comment,client_note';
IF NOT EXISTS (SELECT 1 FROM @Found WHERE ResultType = 'CLIENT' AND EntityId = @ClientId AND Rank = 100)
   OR NOT EXISTS (SELECT 1 FROM @Found WHERE ResultType = 'TASK' AND EntityId = @TaskId AND Rank = 100)
   OR NOT EXISTS (SELECT 1 FROM @Found AS f JOIN crm.ClientTask AS t ON t.PublicId = f.ParentPublicId
                  WHERE f.ResultType = 'TASK_COMMENT' AND t.Id = @TaskId AND f.Snippet LIKE N'%zebrafish%')
    THROW 59153, N'Search should find the client, the task by key first, and text in a task comment.', 1;

-- contacts across clients
INSERT INTO @Contacts EXEC crm.usp_Contact_List @Search = N'', @PageSize = 10;
IF NOT EXISTS (SELECT 1 FROM @Contacts WHERE ContactId = @ContactId AND ClientId = @ClientId AND TotalCount >= 1)
    THROW 59154, N'The contacts list should include the client''s contact.', 1;
PRINT 'ok 26 Today layouts (default, role, own, reset), weekly hours goal, weekly expenses with a receipt read (submit, send back, move, approve), search, contacts';

------------------------------------------------------------------ Done
IF @Keep = 1 COMMIT; ELSE ROLLBACK;
EXEC sp_set_session_context N'TenantId', NULL;
EXEC sp_set_session_context N'UserId', NULL;
PRINT CONCAT('Smoke test passed. ', IIF(@Keep = 1, 'Rows kept for TenantId ', 'Rolled back; TenantId was '), @TenantId, '.');
