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
| sec/ | UserRecentItem (`usp_RecentItem_Touch`, newest 25 per user), AppUser (one login per tenant; CanLogin = 0 for billable people without a login), Role, RolePermission, Permission, DefaultRole(Permission); sign-in tables outside RLS (UserCredential, UserToken, RefreshToken, LoginAudit, ExternalLogin); `usp_Auth_*` sign-in procs (including `usp_Auth_UseRecoveryCode` for MFA recovery codes), `usp_User_Invite`, `usp_SeedTenantRoles`, `fn_UserHasPermission`, `fn_UserPermissions` |
| admin/ | Tenant, TenantType, Plan and PlanSettingDefault (plan-driven features), UserPreference (`usp_UserPreference_Set`) and PlatformFee (one ACCRUED row per issued invoice, a REVERSAL on void); PlatformStatement, PlatformStatementLine, PlatformPayment and TenantPaymentMethod (Pillar's monthly bill and card on file, `usp_PlatformStatement_Generate/RecordPayment/Void`, `usp_PlatformStatementDetail`, `vw_PlatformFeeToDate`); TenantBranding (company block and logo, `usp_TenantBranding_SetLogo`, `usp_TenantLogo`), RemitProfile, Report and ReportParameter (SSRS catalog); settings (SettingDefinition, TenantTypeSettingDefault, TenantSetting, UserSetting, `fn_Setting`, `vw_TenantSetting`, `usp_Setting_Set`, `usp_SeedTenantSettings`); NumberSequence and `usp_NextNumber` for formatted per-tenant counters such as task keys and invoice numbers |
| lkp/ | `SystemCode`, `Default*` masters, tenant lookups, `usp_SyncTenantLookups` |
| ap/ | Vendor, Bill (vendor bills and expense reports), BillLine, BillAttachment, BillPay, BillPayApplication; bill create/submit/approve/reject/void and bill payment apply/unapply/void procs; draft-only line and expense-report flag triggers |
| ar/ | InvoiceRun, InvoiceRunException, Invoice, InvoiceEntry, InvoicePay, CreditMemo, InvoicePayApplication, Refund, InvoiceLayout, InvoiceDocument; `vw_InvoiceDetail` and `usp_InvoiceDetail` (the dataset behind every invoice RDL), `usp_SeedTenantInvoiceLayouts`; invoice run/recalculate/issue/void/delete-draft procs; payment apply/unapply/void, credit memo and refund procs; lock triggers for issued invoices and their lines |
| crm/ | Timesheet (weekly approval unit; `usp_Timesheet_Submit/Approve/Reject`, internal `usp_Timesheet_Ensure` and `usp_Timesheet_SyncStatus`), Client, Contact, Address, ClientAddress, ClientBillingProfile, ClientBillingProfileRecipient, ClientProject, ProjectBillingMilestone, ProjectRate, ProjectUser, ClientTask (temporal, history in ClientTaskHistory), TaskComment, TaskAttachment, TimeEntry; `usp_ClientTask_Create` (the only way to create a task, it assigns the key); `usp_TimeEntry_Save/Submit/Approve/Reject` and `fn_ResolveRate`; `usp_ProjectMilestone_Save/Complete`; triggers for invoiced-time lock, task CompletedAt, milestone total, default billing profile, billing contact fill, billing type rules and rate overlap |
| tools/ | `GenerateLookups.py`, which writes every `lkp` table file and the sync proc |
| Scripts/ | Post-deployment seed (rerunnable MERGE) and `SmokeTest.sql` (run by hand, not on publish) |

## Session context

The API sets `TenantId` and `UserId` in `SESSION_CONTEXT` on every connection. RLS reads `TenantId`; every `CreatedBy` and user column defaults to `UserId`.

## Settings

Read a setting with `admin.fn_Setting(@TenantId, @AppUserId, @Key)` (user, then tenant, then plan, then Pillar default; tenant-type defaults are copied into tenant settings at sign-up). Write only through `admin.usp_Setting_Set`, which enforces Visibility (TENANT_EDIT, TENANT_READ, PLATFORM_ONLY), per-user overrides, type and allowed values.

## Timesheets

Time is approved by the week. `usp_TimeEntry_Save` files each entry on the owner's `crm.Timesheet` (created on demand, starting on
`Timesheet.WeekStartDay`). `usp_Timesheet_Submit`, `_Approve` and `_Reject` act on every entry of the week; the per-entry procs
still work for sending back one entry. The week's status is derived from its entries (REJECTED, OPEN, SUBMITTED, APPROVED).
`Timesheet.LockOnSubmit` and `Timesheet.AllowResubmit` decide whether the person can edit or add to a submitted week, and
`TimeEntry.NoteRequired` makes a description mandatory. An approved week only takes new time from someone with `time.approve`.

## Plans and features

Plans: STANDARD (Flat), AI_POWERED, AI_PLUS, ENTERPRISE, all at the 2.5% fee. Monthly prices and AI allowances are not modelled yet.
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

## Platform fee

Fee per invoice = pre-tax subtotal x rate, capped. Rate and cap come from `admin.[Plan]` (2.5%, no cap) unless the tenant has the hidden
PLATFORM_ONLY settings `Platform.FeeRateOverride` / `Platform.FeeCapOverride` (`Platform.MonthlyMinimumOverride` is for the monthly statement).
Set one as a platform admin: `EXEC admin.usp_Setting_Set @TenantId = 12, @SettingKey = 'Platform.FeeRateOverride', @Value = N'0.02';`
The fee is between Pillar and the tenant only; it never appears on the tenant's invoices to its clients.

Monthly statement (all as platform admin):
1. 1st of the month: `EXEC admin.usp_PlatformStatement_Generate;` bills last month's unbilled fees and reversals per tenant, tops up to the
   monthly minimum (not in a tenant's first month), applies credit carried from the previous statement. Rerunnable.
2. The API charges each OPEN statement's BalanceDue to the tenant's default `admin.TenantPaymentMethod` (processor tokens only, never card numbers)
   and reports every attempt with `admin.usp_PlatformStatement_RecordPayment` (idempotent on the processor charge id). Failure = PAST_DUE.
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

