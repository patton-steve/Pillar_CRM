-- One person's week of time: the unit that is submitted, approved or rejected.
-- Rows are created by crm.usp_Timesheet_Ensure when the first entry for that week is saved; TimeEntry.TimesheetId points here.
-- WeekStart follows Timesheet.WeekStartDay when the sheet is created and never moves afterwards. If the tenant changes the
-- start day, a new sheet is shortened so it never overlaps an existing one (WeekEnd - WeekStart is 0 to 6 days).
-- TimesheetStatusId is derived from the entries by crm.usp_Timesheet_SyncStatus:
--   REJECTED  any entry sent back with a reason and not yet resubmitted
--   OPEN      any unsubmitted entry (or no entries yet)
--   SUBMITTED any entry waiting for approval
--   APPROVED  every entry approved, invoiced or written off
CREATE TABLE crm.Timesheet
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Timesheet PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Timesheet_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    AppUserId           INT             NOT NULL,
    WeekStart           DATE            NOT NULL,
    WeekEnd             DATE            NOT NULL,
    TimesheetStatusId   INT             NOT NULL,
    SubmittedAt         DATETIME2(0)    NULL,      -- last whole-week submit
    SubmittedBy         INT             NULL,
    ApprovedAt          DATETIME2(0)    NULL,      -- last whole-week approve
    ApprovedBy          INT             NULL,
    RejectedAt          DATETIME2(0)    NULL,      -- last whole-week reject
    RejectedBy          INT             NULL,
    RejectedReason      NVARCHAR(500)   NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_Timesheet_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_Timesheet_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    CONSTRAINT UQ_Timesheet_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_Timesheet_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT UQ_Timesheet_User_Week UNIQUE (TenantId, AppUserId, WeekStart),
    CONSTRAINT CK_Timesheet_Week CHECK (WeekEnd >= WeekStart AND WeekEnd <= DATEADD(DAY, 6, WeekStart)),
    CONSTRAINT FK_Timesheet_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id),
    CONSTRAINT FK_Timesheet_Status FOREIGN KEY (TenantId, TimesheetStatusId) REFERENCES lkp.TimesheetStatus (TenantId, Id)
);
GO
-- approval queue
CREATE NONCLUSTERED INDEX IX_Timesheet_Status ON crm.Timesheet (TenantId, TimesheetStatusId, WeekStart) INCLUDE (AppUserId);
