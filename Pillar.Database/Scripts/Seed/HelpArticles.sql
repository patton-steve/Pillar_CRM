/*
Starter Pilo Help articles (19), first written in the React thread and run on PillarDev on 2026-11-03.
This file is the place to edit them. It runs from Script.PostDeployment.sql on every publish:
- It adds missing articles, matched by Slug.
- It updates an existing article only if nobody has edited it in the back office (ModifiedBy IS NULL) and its content
  differs, so back-office edits are never overwritten.
- It never deletes.
Bodies are Markdown; double any single quote ('').
*/
MERGE help.Article AS t
USING (VALUES
    ('getting-started', N'Getting started with Pillar', N'Getting started', N'The order to set things up in when you''re new.', N'setup, first steps, onboarding, configure', 10, 1, N'today,settings',
     N'Set Pillar up in this order and everything else falls into place:

1. **Company details.** Go to **Settings > Company** for your name, address, time zone and currency, then **Settings > Branding** to upload the logo that prints on invoices.
2. **Lists.** Check **Settings > Lists** for payment terms, project types and statuses. Each project type has a key prefix (like WEB) that task numbers start with.
3. **People.** Invite your team from **Settings > Users** and pick a role for each person.
4. **Clients.** Add a client, then a billing profile on its **Billing** tab (payment terms, who gets invoices, invoice layout).
5. **Projects and tasks.** Create a project for the client, add the team and rates, then add tasks.
6. **Time.** Enter time on the **Time** page, submit the week, and approve it if your company uses approval.
7. **Invoices.** Start an **Invoice run** to turn approved time into draft invoices, then issue them.'),
    ('add-a-client', N'Add a client and a billing profile', N'Clients', N'Create a client, then set how and to whom it''s invoiced.', N'new client, customer, billing contact, payment terms', 20, 1, N'clients',
     N'1. Go to **Clients** and click **New client**. A name is all you need to start.
2. Open the client and add contacts on the **Contacts** tab.
3. On the **Billing** tab, add a **billing profile**: payment terms, the billing contact, who else gets the invoice, tax exemption, invoice notes and the **invoice layout**.

A client can have more than one billing profile, for example one per department. Projects use the client''s default profile unless you pick another on the project.

Invoices only go out when the profile has a billing contact. An invoice run skips the client and tells you why if it doesn''t.'),
    ('invoice-layouts', N'Choose an invoice layout', N'Invoicing', N'Summary or time detail, set per billing profile.', N'layout, summary, time detail, S, T, invoice format, PDF', 30, 1, N'clients,invoices',
     N'Each billing profile has an **Invoice layout**:

- **Summary** shows one line per task or item with hours and amount.
- **Time detail** adds each time entry''s description under its task, so the client sees what was done.

Set it on the client''s **Billing** tab when you add or edit a billing profile. **Company default** uses Summary. The layout is saved on each invoice when it''s issued, so changing it later doesn''t change invoices already sent.'),
    ('create-a-project', N'Create a project', N'Projects', N'Projects, teams, rates and the setup checklist.', N'new project, team, rates, budget, fixed fee, milestones', 40, 1, N'projects',
     N'1. Go to **Projects** and click **New project**. Pick the client, the project type and how it bills (hourly, fixed fee or non-billable).
2. Add people on the **Team** tab and their hourly rates on the **Rates** tab.
3. For a fixed fee, add **milestones** on the **Milestones** tab. You can enter each as an amount or a percent, and together they must add up to the fee exactly.

**Setup checklist:** your company can require things before work starts, such as a team or rates. If a check is set to **Required**, the project stays **Planned** and tasks can''t be added until it passes. Admins change these in **Settings > Projects**.'),
    ('tasks', N'Work with tasks', N'Tasks', N'Task numbers, the board, comments and watchers.', N'task, board, kanban, comments, mention, checklist, attachments', 50, 1, N'tasks',
     N'Tasks get a number from their project type''s prefix, like **WEB-12**. Type a number into the search box (Ctrl K) to jump straight to it.

- **List or board:** switch views on the **Tasks** page and drag cards between columns on the board.
- **Task page:** changes save as you make them and show in the comment thread, so there''s a history.
- **Comments:** type **@** to mention someone. They get a notification.
- **Checklist, attachments and watchers** are on the task page too. Watchers get notified about changes.'),
    ('enter-time', N'Enter time', N'Time', N'Quick add, the full form, the timer and the week view.', N'time entry, hours, timesheet, log time, quick add, timer', 60, 1, N'time',
     N'Go to **Time**. The **Day** view shows one day at a time:

- **Quick add:** pick a task, type the time and a description, then click **Add**. The Pilo icon in the description box tidies up your note (see *Polish with Pilo*).
- **Full form:** click an entry to edit it, or use **New > Time entry**. It has the internal note (never shown on invoices) and the Billable switch.
- **Timer:** start one from a task or the top bar. It stops into a time entry, rounded the way your company has set.
- **Week view:** a grid of tasks by day. Click a cell to add or change time.

The time format (decimal hours or hours:minutes) and rounding come from **Settings > Time**.'),
    ('submit-and-approve-time', N'Submit and approve a week', N'Time', N'Why time must be submitted, and how approval works.', N'submit week, approve, reject, approval, timesheet status, locked', 70, 1, N'time,time.approvals',
     N'Time only reaches invoices once its week is **approved**.

1. On **Time**, click **Submit week** when the week is done.
2. If your company requires approval, an approver sees it under **Time > Approvals** and approves it or sends it back with a reason.
3. If approval is turned off in **Settings > Time**, submitting approves the week straight away.

A week that''s sent back shows as **Rejected** with the reason. Fix the entries and submit again. Approved time is locked. An approver can still correct an entry that isn''t on an invoice yet, with a reason that''s kept on its history.'),
    ('polish-with-pilo', N'Polish with Pilo', N'Pilo', N'Let Pilo tidy up a time-entry description.', N'polish, rewrite, AI, note, description, writing style', 80, 1, N'time',
     N'Pilo can rewrite a rough time-entry note into a clear one, which helps when it prints on an invoice.

- In **quick add**, type a note and click the **Pilo icon** in the description box.
- In the **full time form**, click **Polish with Pilo** under Description.

Pilo shows a suggestion. Click **Use this**, **Try again** or **Dismiss**. Nothing is saved until you save the entry.

Pilo writes in your **writing style** (Plain, Friendly, Formal or Concise). Admins set the company default and writing rules in **Settings > Pilo**. Polishing never counts toward your monthly Pilo reports.'),
    ('run-invoices', N'Run invoices', N'Invoicing', N'Turn approved time and expenses into draft invoices.', N'invoice run, billing run, generate invoices, drafts, preview, nothing to bill', 90, 1, N'invoices',
     N'1. Go to **Invoices** and click **New invoice run**.
2. Pick the date to bill through, and optionally one client or project. The preview shows what''s ready to bill and what''s **waiting** (time not submitted or not approved yet).
3. Click **Create drafts**. Pillar makes one draft per client billing profile and lists anything it **skipped**, with a **Fix** link.
4. Pick the drafts to issue, check them in **Preview**, then **Issue**. Invoice numbers are given when an invoice is issued.

If nothing is ready, no run is saved. A run shows **Open** while it has drafts left and **Completed** once they''re all issued. You can delete a run that hasn''t issued anything.'),
    ('issue-void-credit', N'Issue, void or credit an invoice', N'Invoicing', N'Editing drafts, issuing, PDFs, voids and credit memos.', N'issue invoice, void, credit memo, PDF, edit draft, invoice number', 100, 1, N'invoices',
     N'- **Drafts** can be edited: add or change lines, notes and dates. Delete a draft and its work bills again next run.
- **Issue** gives the invoice its number and makes the PDF. Issued invoices can''t be edited.
- **PDF:** open the invoice and click **PDF**, or use the PDF button in an invoice list (including the client''s **Invoices** tab).
- **Void** cancels an issued invoice that has no payments, and its work can bill again.
- **Credit memo** reduces what a client owes without voiding the invoice. The credit can be applied to this or another invoice.'),
    ('record-a-payment', N'Record a payment', N'Payments', N'Apply money received to open invoices.', N'payment, receive, apply, deposit, overpayment, credit, unapply', 110, 1, N'payments,invoices',
     N'1. Go to **Payments** and click **Record payment**, or use **New > Payment**.
2. Pick the client, the amount, the date and the method.
3. Pillar applies it to the oldest open invoices first. Change the amounts if the client told you which invoices it''s for.

Anything not applied stays as **client credit** and can be applied later. To fix a mistake, **unapply** it from an invoice or **void** the payment.'),
    ('ar-aging', N'See who owes you (aging)', N'Invoicing', N'The aging report shows what''s owed and how late.', N'aging, AR, receivables, overdue, past due, owed', 120, 1, N'invoices',
     N'**Invoices > Aging** shows each client''s open balance split into current, 1-30, 31-60, 61-90 and over 90 days late, plus any unapplied credit.

Click a client to open its invoices. Late invoices also show **N days late** in invoice lists.'),
    ('invite-users', N'Invite people and manage users', N'Settings', N'Invites, roles, rates and turning off a login.', N'invite, user, add user, seat, deactivate, remove login, resend invite', 130, 1, N'settings.users',
     N'Go to **Settings > Users**.

- **Invite:** enter the person''s name, email and role. They get an email to set a password. You can resend or cancel the invite.
- **Edit:** click a person to change their role, rates or time zone, or their sign-in email.
- **Turn off a login** when someone leaves. Their history stays.
- **People without a login** can be added for billable work, and don''t use a seat.

Each plan includes some seats. Extra seats are billed monthly, shown in **Settings > Billing & plan**.'),
    ('roles-and-permissions', N'Roles and permissions', N'Settings', N'What each role can do, and making your own.', N'role, permission, owner, admin, access, custom role', 140, 1, N'settings.roles',
     N'**Settings > Roles** shows a grid of what each role can do.

- The built-in roles are a starting point. **Owner** can do everything.
- **Copy** a role to make your own, then turn permissions on or off. Changes apply straight away.
- **Make default** sets the role new invites start with.
- **Retire** a custom role you no longer use. People who have it need a new role first.'),
    ('lists-and-custom-fields', N'Lists and custom fields', N'Settings', N'Drop-down values and extra fields on records.', N'lists, dropdown, statuses, project types, payment terms, custom field', 150, 1, N'settings.lists,settings.custom-fields',
     N'- **Settings > Lists** holds every drop-down: statuses, project and task types, payment terms and more. Add values, rename them, reorder them, or retire ones you don''t use. **Works like** ties a status to how Pillar treats it, for example Done.
- **Settings > Custom fields** adds fields to clients, contacts, projects, tasks, vendors and bills. Pick a type (text, number, date, yes/no or a choice list), and whether it''s required or shows in lists. A field''s key and type can''t change once saved.'),
    ('company-branding-email', N'Company details, logo and email', N'Settings', N'Your company info, invoice logo, mail server and templates.', N'company, logo, branding, email, SMTP, template, merge fields', 160, 1, N'settings.company,settings.branding,settings.email',
     N'- **Settings > Company:** name, address, time zone and dashboard options.
- **Settings > Branding:** upload a PNG or JPEG logo up to 512 KB. It prints on invoices.
- **Settings > Email:** enter your mail server and send a test. Edit the invoice email templates and insert merge fields like the invoice number and amount due. The preview fills them with sample values.'),
    ('notifications-and-profile', N'Your profile and notifications', N'Settings', N'Name, avatar, signature and which notifications you get.', N'profile, avatar, photo, Pilo avatar, signature, notifications, bell', 170, 1, N'settings.profile,settings.my-notifications',
     N'- **Settings > Profile:** your name, title, phone, time zone and email signature. For your avatar, choose your initials, a photo, or a Pilo in your own colours. It shows at the top right.
- **Settings > My notifications:** choose which notifications you get. Some may be locked on by your company.
- The **bell** at the top lists your notifications, newest first. Dismiss them one at a time or all at once.'),
    ('billing-and-plan', N'Your Pillar plan and billing', N'Billing & plan', N'Plans, seats, Pilo allowance and statements.', N'plan, upgrade, downgrade, seats, statement, card, Pilo allowance, price', 180, 1, N'settings.billing',
     N'**Settings > Billing & plan** shows your plan, seats, this month''s Pilo use and your monthly statements.

- **Plans:** Flat has no Pilo AI. AI Powered ($39/month) includes 60 Pilo reports, AI Powered Plus ($89) 200, and Enterprise ($209) 500. Reports over the allowance are billed per report, and you can set an overage cap.
- **Seats:** extra users are $12 per user per month on every plan.
- **Change plan** shows what changes before you confirm.
- **Statements** list what Pillar charged each month.

Pilo Help is included in every plan.'),
    ('ask-pilo', N'Ask Pilo for reports', N'Pilo', N'Ask questions in plain words and get charts, lists or help.', N'ask pilo, AI report, chart, search, find, saved report, help', 190, 1, N'reports',
     N'Go to **Reports**, or click the Pilo icon at the top. Type a question and pick what you want back:

- **Report:** a chart and table from your data, such as *billable hours by client for the last 90 days*. Change the dates or client and click **Run again**. That''s free and doesn''t call Pilo again.
- **Find:** a list of matching records you can click through to, such as *invoices more than 30 days late*.
- **Help:** how-to answers from these help articles.

**Save** a report to keep it under **Saved reports** and re-run it on today''s data any time, for free. **Share** it to make it a company report (Enterprise).

Each new report counts toward your monthly allowance. Find has its own monthly limit, and Help never counts. Pilo only sees your own company''s data, and only what your role is allowed to see.')
) AS s (Slug, Title, Category, Summary, Keywords, SortOrder, IsPublished, ScreenTags, Body)
ON t.Slug = s.Slug
WHEN MATCHED AND t.ModifiedBy IS NULL
     AND (t.Title <> s.Title OR t.Category <> s.Category OR t.Body <> s.Body OR t.SortOrder <> s.SortOrder
          OR t.IsPublished <> s.IsPublished
          OR ISNULL(t.Summary, N'') <> ISNULL(s.Summary, N'') OR ISNULL(t.Keywords, N'') <> ISNULL(s.Keywords, N'')
          OR ISNULL(t.ScreenTags, N'') <> ISNULL(s.ScreenTags, N''))
    THEN UPDATE SET Title = s.Title, Category = s.Category, Summary = s.Summary, Keywords = s.Keywords,
                    SortOrder = s.SortOrder, IsPublished = s.IsPublished, ScreenTags = s.ScreenTags, Body = s.Body,
                    PublishedAt = CASE WHEN s.IsPublished = 1 THEN COALESCE(t.PublishedAt, SYSUTCDATETIME()) ELSE t.PublishedAt END,
                    ModifiedAt = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET
    THEN INSERT (Slug, Title, Summary, Body, Category, Keywords, SortOrder, IsPublished, Source, PublishedAt, ScreenTags)
         VALUES (s.Slug, s.Title, s.Summary, s.Body, s.Category, s.Keywords, s.SortOrder, s.IsPublished, 'MANUAL',
                 IIF(s.IsPublished = 1, SYSUTCDATETIME(), NULL), s.ScreenTags);
