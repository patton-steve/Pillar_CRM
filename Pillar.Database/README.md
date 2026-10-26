# Pillar.Database

SDK-style SQL Database Project (Microsoft.Build.Sql). The database is the schema source of truth;
the Python API maps to these tables and never generates DDL.

## Build and publish

```
dotnet build                     # produces bin/Debug/Pillar.Database.dacpac
sqlpackage /Action:Publish /SourceFile:bin/Debug/Pillar.Database.dacpac \
  /TargetServerName:localhost /TargetDatabaseName:Pillar /TargetTrustServerCertificate:true
```

If you change objects directly in SSMS, pull them back into the project with Schema Compare
(VS Code SQL Database Projects extension or Visual Studio) before the next publish, or publish will revert them.

## Local setup plan

1. Copy this folder to a working folder on your machine and put it under git (private repo).
2. Install the .NET 8 SDK and `sqlpackage` (`dotnet tool install -g microsoft.sqlpackage`); SQL Server 2019 or later locally (the project targets 2019).
3. `dotnet build`, then publish to a new, empty database (`/TargetDatabaseName:Pillar`). Until the first real deploy, drop and recreate it rather than publishing over an old copy: later handoffs add NOT NULL columns and FKs (users, plans) that old test rows would fail.
4. **Smoke test.** Open `Scripts/SmokeTest.sql` in SSMS against that database and run it (or `sqlcmd -S <server> -d <db> -E -C -b -I -i Scripts\SmokeTest.sql`; keep `-I`). It walks one tenant from sign-up through
   client, contact, project, task, time, invoice run, issue, payments and void, then a paid vendor bill whose billable expense is rebilled on the next run, asserting each step, then rolls back. Every line should print `ok`.
   First passed on 2026-10-20 against SQL Server 2019 Express (all 16 checks).
5. Publish again to confirm the post-deploy seed is rerunnable and that a no-change publish has nothing to do.
   (`/Action:DeployReport` should list no table rebuilds. RLS refuses rebuilds of tenant tables; never publish with `AllowUnsafeRowLevelSecurityDataMovement=true`, since the copy runs through the RLS filter and can drop other tenants' rows.)

## Layout

| Folder | Holds |
|---|---|
| Security/ | Schemas, RLS predicate and `sec.TenantIsolationPolicy` (add every new tenant table here), `sec.usp_ReportContext_Set` |
| sec/ | UserLegalAcceptance (`usp_Legal_Accept`), SupportAccessGrant and ImpersonationSession (`usp_SupportAccess_Grant/Revoke/Get`, `usp_Impersonation_Start/End/Check`), UserAnnouncementDismissal (`usp_Announcement_Dismiss`), `usp_Auth_VerifyEmail` and `usp_Auth_RequestEmailVerification`; UserAvatar (`usp_UserAvatar_Set/Get`), `usp_UserProfile_Save`, `usp_User_ChangeEmail` (admin only), `usp_Session_List/Revoke`, `usp_Auth_SecurityPolicy`, `fn_NotificationChannels`, `usp_Notification_Dismiss`; Notification, NotificationType, UserNotificationSetting (the bell: `usp_Notification_Raise/List/MarkRead`, `usp_NotificationSetting_Get/Set`, `fn_NotificationRecipients`); UserRecentItem (`usp_RecentItem_Touch`, newest 25 per user), AppUser (one login per tenant; CanLogin = 0 for billable people without a login), Role, RolePermission, Permission, DefaultRole(Permission); sign-in tables outside RLS (UserCredential, UserToken, RefreshToken, LoginAudit, ExternalLogin); `usp_Auth_*` sign-in procs (including `usp_Auth_UseRecoveryCode` for MFA recovery codes), `usp_User_Invite`, `usp_SeedTenantRoles`, `usp_Role_Save`, `usp_RolePermission_Set` and `usp_RolePermission_Grid` (custom roles and the permission grid, grouped by PermissionCategory), `fn_UserHasPermission`, `fn_UserPermissions` |
| admin/ | RoleDashboardLayout (Today layout per role: `usp_RoleDashboardLayout_Publish/List`, `usp_TodayLayout_Get/Reset`), Tenant lifecycle (`usp_Tenant_SubmitApplication`, `usp_Tenant_Approve/Decline/SetStatus/SetPlan/SetOverride`), TenantPlanChange (`usp_PlanChange_Check/Request/Cancel/ApplyDue`, `fn_PlanChangeIssues`), TenantSeatDaily and `fn_TenantSeats` (`usp_Seats_Get`), `fn_PiloUsage` (`usp_PiloUsage_Get`), LegalDocument (`usp_LegalDocument_Publish/Current`), Announcement (`usp_Announcement_Save/List`), sample company (`usp_SampleData_Load/Remove`); Pillar-only back office outside RLS: PlatformAudit (append-only), PlatformNotification (inbox), PlatformTenantNote, with `usp_PlatformDashboard`, `usp_PlatformTenant_List/Get`, `usp_PlatformFailedCharges`, `usp_PlatformStatement_MarkPaid`, `usp_PlatformPiloCost`, `usp_PlatformUser_Update`, `usp_PlatformAudit_List`, `usp_PlatformNotification_List/MarkRead/MarkEmailed`; AuditLog (append-only; `usp_Audit_Write`, `usp_AuditLog_List`), ImportJob and ImportRow (`usp_Import_Stage/Validate/Commit` for CSV clients and contacts), TenantNotificationDefault (`usp_TenantNotificationDefault_Get/Set`), PiloEmote; TenantEmailSetting, EmailTemplate and EmailLog (tenant SMTP, invoice email templates, outbound log: `usp_TenantEmailSetting_Save/RecordTest`, `usp_EmailTemplate_Save`, `usp_SeedTenantEmailTemplates`, `fn_EmailTemplateFor`, `usp_EmailLog_Queue/SetStatus`); SavedReport (`usp_SavedReport_Save/Delete/List/MarkRun`, RenderType from ReportRenderType), ReportCategory and `usp_Report_ListCanned` (canned report cards) and ReportParameterSet (`usp_ReportParameterSet_Save`) for the Reports page; ProjectSetupCheck and TenantProjectSetupCheck (`usp_ProjectSetupCheck_Get/Set`); Tenant, TenantType, Plan and PlanSettingDefault (plan-driven features), UserPreference (`usp_UserPreference_Set`); custom fields (CustomFieldDefinition, CustomFieldOption, CustomFieldValue, `vw_CustomFieldValue`, `usp_CustomField_Save/Reorder`, `usp_CustomFieldValues_Get/Save`); PlatformFee (one ACCRUED row per issued invoice, a REVERSAL on void); PlatformStatement, PlatformStatementLine, PlatformPayment and TenantPaymentMethod (Pillar's monthly bill and card on file, `usp_PlatformStatement_Generate/RecordPayment/Void`, `usp_PlatformStatementDetail`, `vw_PlatformFeeToDate`); TenantBranding (company block and logo, `usp_TenantBranding_SetLogo`, `usp_TenantLogo`), RemitProfile, Report and ReportParameter (SSRS catalog); settings (SettingDefinition, TenantTypeSettingDefault, TenantSetting, UserSetting, `fn_Setting`, `vw_TenantSetting`, `usp_Setting_Set`, `usp_SeedTenantSettings`); NumberSequence and `usp_NextNumber` for formatted per-tenant counters such as task keys and invoice numbers |
| lkp/ | `SystemCode`, `Default*` masters, tenant lookups, `usp_SyncTenantLookups` |
| ap/ | Weekly expenses (`usp_Expense_Save/List`: one expense report per timesheet week, Bill.TimesheetId; Pilo receipt reads on BillLine), Vendor, Bill (vendor bills and expense reports), BillLine, BillAttachment, BillPay, BillPayApplication; bill create/submit/approve/reject/void and bill payment apply/unapply/void procs; draft-only line and expense-report flag triggers |
| ar/ | InvoiceRun, InvoiceRunException, Invoice, InvoiceEntry, InvoicePay, CreditMemo, InvoicePayApplication, Refund, InvoiceLayout, InvoiceDocument; `vw_InvoiceDetail` and `usp_InvoiceDetail` (the dataset behind every invoice RDL), `usp_SeedTenantInvoiceLayouts`; invoice run/recalculate/issue/void/delete-draft procs; payment apply/unapply/void, credit memo and refund procs; lock triggers for issued invoices and their lines |
| crm/ | `usp_Search` (global search, LIKE), `usp_Contact_List` (contacts across clients), `usp_WeeklyHours_Get` and `fn_WeekFor` (hours against Time.WeeklyHoursGoal), Timesheet (weekly approval unit; `usp_Timesheet_Submit/Approve/Reject`, `usp_Timesheet_ListForApproval` for the Approvals tabs, internal `usp_Timesheet_Ensure` and `usp_Timesheet_SyncStatus`), Client, Contact, Address, ClientAddress, ClientBillingProfile, ClientBillingProfileRecipient, ClientProject, ProjectBillingMilestone, ProjectRate, ProjectUser, ClientNote and ClientNoteMention (`usp_ClientNote_Save`, `vw_ClientActivity` feed), ProjectBudgetAlert (`usp_Project_CheckBudgetAlerts`), `fn_ProjectSetupIssues` and `usp_Project_SetupStatus`, ClientTask (temporal, history in ClientTaskHistory), TaskComment and TaskCommentMention (`usp_TaskComment_Save`; `usp_ClientTask_UpdateDetails` saves status, assignee, due date and estimate with a change comment whose ChangeJson holds the chips), TaskWatcher (`usp_TaskWatcher_Set`), TaskChecklistItem (`usp_TaskChecklist_Save`), TaskAttachment, TimeEntry; `usp_ClientTask_Create` (the only way to create a task, it assigns the key); `usp_TimeEntry_Save/Submit/Approve/Reject` and `fn_ResolveRate`; `usp_TimeEntry_Update` (approver edits to approved time, logged in TimeEntryChange); `usp_ProjectMilestone_Save/Complete`; triggers for invoiced-time lock, task CompletedAt, milestone total, default billing profile, billing contact fill, billing type rules and rate overlap |
| support/ | Ticket and TicketMessage (tenants open tickets from Help, Pillar answers in the back office): `usp_Ticket_Open/Reply/SetStatus/List/Get` |
| help/ | Article (help articles for Pilo Help, edited in the back office): `usp_Article_Save/List/Get` |
| ai/ | Generation (one row per Pilo model call: tokens, cost, CountsTowardQuota), `usp_Generation_Log` |
| tools/ | `GenerateLookups.py`, which writes every `lkp` table file and the sync proc |
| Scripts/ | Post-deployment seed (rerunnable MERGE) and `SmokeTest.sql` (run by hand, not on publish) |

## Session context

The API sets `TenantId` and `UserId` in `SESSION_CONTEXT` on every connection. RLS reads `TenantId`; every `CreatedBy` and user column defaults to `UserId`.
Also: `ClientIp` (audit rows), `IsPlatformAdmin` (back-office routes only, for platform admins who signed in with MFA) and, on a Pillar support
sign-in, `ImpersonationSessionId` (stamped on every audit row made during it).

## Settings

Read a setting with `admin.fn_Setting(@TenantId, @AppUserId, @Key)` (user, then tenant, then plan, then Pillar default; tenant-type defaults are copied into tenant settings at sign-up). Write only through `admin.usp_Setting_Set`, which enforces Visibility (TENANT_EDIT, TENANT_READ, PLATFORM_ONLY), per-user overrides, type and allowed values.

## Timesheets

Time is approved by the week. `usp_TimeEntry_Save` files each entry on the owner's `crm.Timesheet` (created on demand, starting on
`Timesheet.WeekStartDay`). `usp_Timesheet_Submit`, `_Approve` and `_Reject` act on every entry of the week; the per-entry procs
still work for sending back one entry. The week's status is derived from its entries (REJECTED, OPEN, SUBMITTED, APPROVED).
`Timesheet.LockOnSubmit` and `Timesheet.AllowResubmit` decide whether the person can edit or add to a submitted week, and
`TimeEntry.NoteRequired` makes a description mandatory. An approved week only takes new time from someone with `time.approve`.
The Approvals tabs come from `usp_Timesheet_ListForApproval` (SUBMITTED, APPROVED, REJECTED, COMPLETE; COMPLETE is computed:
approved with no billable time left off an issued invoice). An approver can send back an approved week while none of it is
on an invoice, or fix approved entries in place with `usp_TimeEntry_Update`, which needs a reason and logs the changes.

Expenses go in with the week (handoff 23). `ap.usp_Expense_Save` files each expense on the owner's expense report for that
timesheet week (`ap.Bill.TimesheetId`, created with the first expense). Submitting, approving or sending back the week does the
same to its report; the bill procs refuse a weekly report. The report follows `AP.RequireApproval`, the time follows
`TimeEntry.RequireApproval`, and the week's status counts the report like one more entry. A Pilo receipt read is logged in
`ai.Generation` as RECEIPT and doesn't count toward the report allowance unless `Pilo.ReceiptsCountTowardQuota` is on.

## Email

Phase 1 sends nothing; the schema is ready for bulk invoice email through each tenant's own SMTP server. `admin.TenantEmailSetting`
holds the server and a secret reference (never the password). Templates live in `admin.EmailTemplate` (one default per type,
seeded at sign-up); a billing profile may pick its own (`InvoiceEmailTemplateId`), resolved by `admin.fn_EmailTemplateFor`.
`usp_EmailLog_Queue` records each send for the invoice timeline.

## Roles

Tenants can add roles (`sec.usp_Role_Save`, usually copying a system role; `BaseRoleCode` keeps its archetype) and edit any
role's permissions except Owner's (`sec.usp_RolePermission_Set`). An edited role is marked `PermissionsCustomizedAt`, and
`usp_SeedTenantRoles` never adds permissions to it, so a permission a tenant turned off stays off (and new ones arrive off).
The grid is data-driven: `sec.PermissionCategory` holds the headers and `sec.Permission` (CategoryCode, Description,
IsActive) the toggles; `sec.usp_RolePermission_Grid` returns both. Adding a permission is a post-deploy row, no UI change.
A retired permission (IsActive = 0) keeps its grants but counts for nobody.

## Plans and features

Plans: STANDARD (Flat), AI_POWERED, AI_PLUS, ENTERPRISE, all at the 2.5% fee. `admin.[Plan]` holds the price ($0 / $39 / $89 / $209), included seats
(2 / 5 / 10 / 20), the extra seat price ($12 per user per month on every plan) and the Pilo allowance (60 / 200 / 500 reports, overage $0.75 / $0.50 / $0.35).
A seat is a login (CanLogin = 1, not disabled). Past the included seats, only `billing.manage` holders can add a login (`sec.trg_AppUser_Rules`).
Custom quotes: PLATFORM_ONLY `Seats.IncludedOverride`, `Seats.ExtraPriceOverride`, `Pilo.MonthlyReportsOverride`. `Tenant.MaxUsers` is now only a hard cap Pillar may set.
Plan changes go through `admin.usp_PlanChange_Request`: upgrades apply now, downgrades wait for the 1st (`usp_PlanChange_ApplyDue`, daily job).
Saved Pilo reports are limited by `Pilo.SavedReportsPerUser` (5 / 10 / 25) and `Pilo.CompanyReports` (50 on Enterprise only).
`admin.PlanSettingDefault` gives a plan's tenants a setting value (Feature.Pilo on the AI plans, Feature.ExtendedBranding on AI_PLUS
and ENTERPRISE). `admin.fn_Setting` resolves user, then tenant, then plan, then Pillar default, so a plan change takes effect at once.

## Writing computed columns and defaults

Use `CONVERT(type, expr)`, never `CAST(expr AS type)`, in computed columns and DEFAULT constraints. SQL Server stores both as `CONVERT`, and sqlpackage doesn't see the CAST form as equal, so every publish would drop and re-add those columns and rebuild the table (which RLS blocks). `tools/GenerateLookups.py` already emits CONVERT.

## Lookup pattern

Every lookup is a pair: `lkp.Default<Name>` (Pillar master, no TenantId) and `lkp.<Name>` (tenant list).
Same columns on all: `Code, Name, SortOrder, IsActive, IsCustom, IsLocked, DefaultId, SystemCode`.
`SystemCode` is FK-checked against `lkp.SystemCode` through a persisted `LookupName` column, so a tenant
can add any number of values but each maps to a behavior Pillar defines. Core tables use composite FKs
`(TenantId, XxxId) -> lkp.Xxx (TenantId, Id)`.

To add a lookup, add it to the LOOKUPS list in `tools/GenerateLookups.py` and run `python3 tools/GenerateLookups.py .` rather than hand-writing the pair.

New tenant: `EXEC admin.usp_Tenant_SignUp ...` does everything (tenant, lookups, settings, invoice layouts, roles, owner login).
New default added: `EXEC lkp.usp_SyncTenantLookups;` (all tenants, needs IsPlatformAdmin session context).

## Invoice rendering

The starter RDLs live in `../Pillar.Reports` (`Invoice_Summary.rdl` = S, `Invoice_TimeDetail.rdl` = T). Both take `TenantId` and `InvoicePublicId`
and use two datasets: `ar.usp_InvoiceDetail` (one flat dataset; `@IncludeTimeDetail` 0 for S, 1 for T) and `admin.usp_TenantLogo`.
Their embedded data source points at `localhost/Pillar` with Windows auth; repoint it (or swap in a shared data source) when you deploy.
Report procs call `sec.usp_ReportContext_Set`, which sets `TenantId` in session context when SSRS connects without one, so RLS still applies.
SSRS should be reachable only by the API, never by tenants directly.
Layout and remit resolve as invoice, then billing profile, then the tenant default; `ar.usp_Invoice_Issue` snapshots both.

## Fixed-fee milestones

A FIXED project can have a billing schedule in `crm.ProjectBillingMilestone`. The UI saves the whole schedule with
`crm.usp_ProjectMilestone_Save` (JSON array; each entry is an amount or a percent of the fee, stored as an amount).
The schedule must total `FixedFeeAmount` exactly, and `crm.trg_ClientProject_MilestoneTotal` keeps it that way if the fee is edited directly.
Triggers: DATE bills once `BillDate` is reached, MANUAL once someone marks it done (`crm.usp_ProjectMilestone_Complete`), TASK once its task is DONE.
`ar.usp_InvoiceRun_Generate` turns each ready milestone into one FIXED_FEE line; void and draft delete release it to bill again.
Invoiced milestones are locked; a change order adds milestones and raises the fee in the same save.

## Custom fields

Tenants add their own fields to clients, contacts, projects, tasks, vendors and bills (Settings > Custom fields, needs `settings.custom_fields`).
Types: TEXT (max length up to 400), INT, DECIMAL, DATE, BIT (yes/no) and LIST (choices in `admin.CustomFieldOption`).
`admin.CustomFieldValue` holds one typed row per record per field that has a value, with filtered indexes per type for list filters and search.
Record pages call `admin.usp_CustomFieldValues_Get` (no rows = hide the section) and `admin.usp_CustomFieldValues_Save` (JSON keyed by FieldKey).
List pages and reports join `admin.vw_CustomFieldValue` on EntityType + RecordId. Retiring a field or a used choice keeps existing values.

## Notifications

The header bell reads `sec.Notification` through `sec.usp_Notification_List` and `usp_Notification_MarkRead` (each user sees only their own).
`sec.usp_Notification_Raise` is the only writer: it finds recipients (`sec.fn_NotificationRecipients`), skips the actor, inactive users and anyone who turned the type off, and refreshes an unread duplicate instead of adding another.
Raised by the database: task created, assigned or status changed (`crm.trg_ClientTask_Notify`), new project on a client (`crm.trg_ClientProject_Notify`), mentions and new comments, timesheet submitted or sent back, bill waiting for approval, invoice paid, and budget alerts.
`crm.usp_Project_CheckBudgetAlerts` must be called by the API after time is saved or approved, and nightly per tenant. It notifies once per threshold (`Project.BudgetAlertPercents`, or the project's own `BudgetAlertPercents`).

## Project setup checks

`admin.ProjectSetupCheck` is Pillar's catalog of 11 checks: TEAM, RATE, BUDGET, FEE, MILESTONES, PROJECT_MANAGER, START_DATE, END_DATE, PO_NUMBER, BILLING_CONTACT and REQUIRED_CUSTOM_FIELDS.
Each check has AppliesTo (ALL or a list of billing types) and a default level.
Tenants set each check to OFF, WARN or BLOCK in Settings > Projects. The levels are stored in `admin.TenantProjectSetupCheck` and edited with `admin.usp_ProjectSetupCheck_Get/Set` (needs `settings.projects`).
The defaults are: TEAM, RATE (hourly and NTE), BUDGET (hourly) and FEE (fixed and retainer) BLOCK; MILESTONES (fixed) WARN; the rest OFF.
`crm.fn_ProjectSetupIssues` lists the failing checks. While any BLOCK remains, `crm.usp_ClientTask_Create` refuses tasks and `crm.trg_ClientProject_SetupGate` keeps the project in PLANNED.
The project page calls `crm.usp_Project_SetupStatus` and hides its setup card once `@IsReady = 1`.

## Platform fee

Fee per invoice = pre-tax subtotal x rate, capped. Rate and cap come from `admin.[Plan]` (2.5%, no cap) unless the tenant has the hidden
PLATFORM_ONLY settings `Platform.FeeRateOverride` / `Platform.FeeCapOverride` (`Platform.MonthlyMinimumOverride` is for the monthly statement).
Set one as a platform admin: `EXEC admin.usp_Setting_Set @TenantId = 12, @SettingKey = 'Platform.FeeRateOverride', @Value = N'0.02';`
The fee is between Pillar and the tenant only; it never appears on the tenant's invoices to its clients.

Monthly statement (all as platform admin):
1. 1st of the month: `EXEC admin.usp_PlanChange_ApplyDue;` then `EXEC admin.usp_PlatformStatement_Generate;` bills last month's unbilled fees and
   reversals per tenant, the plan price by day (PLAN, prorated across plan changes), extra seats at the month's peak (SEATS), Pilo overage (PILO,
   capped by the tenant's `Pilo.OverageCapAmount`), tops fees up to the monthly minimum (not in a tenant's first month), applies credit carried
   from the previous statement. Subscription lines are billed in arrears. Rerunnable.
2. The API charges each OPEN statement's BalanceDue to the tenant's default `admin.TenantPaymentMethod` (processor tokens only, never card numbers)
   and reports every attempt with `admin.usp_PlatformStatement_RecordPayment` (idempotent on the processor charge id). Failure = PAST_DUE, with
   `NextRetryAt` 1, 3, then 5 days later (the API's retry job charges statements whose NextRetryAt has passed). `usp_PlatformStatement_MarkPaid`
   settles one by hand with a reason.
3. To correct a month: `admin.usp_PlatformStatement_Void` (unpaid only), fix the override, generate again with `@PeriodStart` and `@TenantId`.
Tenants see `admin.vw_PlatformFeeToDate` and their statements read-only under Settings > Billing; PDF = `../Pillar.Reports/PlatformStatement.rdl`.

## User FKs

Every person column (TimeEntry, ProjectUser, ProjectRate, task assignee/reporter, comment author, project manager, expense payee, UserSetting)
has a composite FK to `sec.AppUser (TenantId, Id)`. Audit columns (CreatedBy, ModifiedBy, ApprovedBy, ...) deliberately have none.

## Users and sign-in

One `sec.AppUser` per person per tenant; a login email is unique across Pillar. The API checks permissions with
`sec.fn_UserHasPermission(@TenantId, @UserId, 'time.approve')`; owners hold every permission. Seeded roles: Owner, Admin, Manager, Billing, Member.
Sign-in tables sit outside RLS because they are read before the tenant is known: grant the API EXECUTE on the `sec.usp_Auth_*` procs and no direct
SELECT on `sec.UserCredential`, `UserToken` or `RefreshToken`. Passwords arrive as bcrypt hashes and tokens as SHA-256 hashes; the database never sees either in clear.
Sign-in: `usp_Auth_GetLogin` -> API checks bcrypt (and TOTP) -> `usp_Auth_RecordLogin` (5 failures lock 15 minutes) -> `usp_Auth_IssueRefreshToken`;
refresh with `usp_Auth_RotateRefreshToken` (reuse revokes the family); invites and resets with `usp_User_Invite` / `usp_Auth_RequestPasswordReset` and `usp_Auth_RedeemToken`.

## Admin settings, audit and notifications

Each settings page has its own permission (`settings.company`, `settings.time`, `settings.email` ... `settings.audit`; the
old `settings.edit` is retired). `admin.SettingDefinition.PermissionCode` says which page guards a setting, and
`admin.usp_Setting_Set` checks it. Every admin proc writes `admin.AuditLog` through `admin.usp_Audit_Write`; the API calls
the same proc for admin writes it makes directly (for example lookup lists) and sets `SESSION_CONTEXT(N'ClientIp')`.
Notifications have two channels: in-app and email. `sec.fn_NotificationChannels` resolves a person's choice, then the
tenant default (`admin.TenantNotificationDefault`, which can lock a channel on), then Pillar's. Email is stored now and
sent later: rows with `SendEmail = 1` and no `EmailedAt` are waiting for the email job, which honors the user preferences
`notify.digest` (INSTANT, DAILY, WEEKLY) and `notify.quietStart` / `notify.quietEnd`.

## Sign-up, approval and the back office

Sign-up is an application (Steve 2026-10-22). `admin.usp_Tenant_SignUp` (current terms accepted, VERIFY link stored) creates the tenant in SETUP;
the owner verifies the email (`sec.usp_Auth_VerifyEmail`), works through the setup wizard and calls `admin.usp_Tenant_SubmitApplication`
(PENDING_REVIEW; Pillar's inbox gets the application and it is emailed to the platform admins). Pillar approves (`admin.usp_Tenant_Approve`,
optionally setting plan, seats and fee overrides) or declines it. Team invites open once the tenant is ACTIVE. `sec.usp_Auth_GetLogin` and
`sec.usp_Auth_SecurityPolicy` return TenantStatus, EmailVerified and MustAcceptTermsId so the API can route each sign-in.
The back office is the same app: platform admins (`sec.AppUser.IsPlatformAdmin`, MFA required) on back-office routes, where the API sets
`IsPlatformAdmin`. Every back-office change writes `admin.PlatformAudit` with its reason. "Log in as" needs the tenant's live
`sec.SupportAccessGrant` (Settings > Security); the support session and everything done in it show in the tenant's audit log.
Pillar-only tables (PlatformAudit, PlatformNotification, PlatformTenantNote) are outside RLS: never grant the API SELECT on them.
