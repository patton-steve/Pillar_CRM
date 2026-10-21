-- Time logged against a task. How time is entered is the tenant setting TimeEntry.EntryMode:
--   HOUR / HALF_HOUR / QUARTER_HOUR = duration in that increment; EXACT = hours:minutes typed in;
--   START_END = start and end clock times (EndTime NULL = timer running, draft only).
-- EntryMode is copied onto each row, so changing the setting never reinterprets old entries.
-- EnteredMinutes is what the user logged; BilledMinutes applies TimeEntry.RoundingMinutes (EXACT and START_END only).
-- Rate is re-resolved on every save and frozen at approval. Write through the crm.usp_TimeEntry_* procs.
CREATE TABLE crm.TimeEntry
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TimeEntry PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TimeEntry_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    ProjectId           INT             NOT NULL,
    TaskId              INT             NOT NULL,
    AppUserId           INT             NOT NULL CONSTRAINT DF_TimeEntry_AppUserId DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    WorkDate            DATE            NOT NULL,
    EntryMode           VARCHAR(12)     NOT NULL,
    StartTime           TIME(0)         NULL,
    EndTime             TIME(0)         NULL,      -- earlier than StartTime = crossed midnight
    EnteredMinutes      INT             NULL,      -- NULL only while a timer is running
    BilledMinutes       INT             NULL,
    Hours               AS CONVERT(DECIMAL(9,4), BilledMinutes / 60.0) PERSISTED,
    Description         NVARCHAR(2000)  NULL,      -- prints on the invoice
    InternalNote        NVARCHAR(2000)  NULL,      -- never prints
    IsBillable          BIT             NOT NULL,
    RateApplied         DECIMAL(19,4)   NULL,
    RateSource          VARCHAR(10)     NULL,      -- USER_TASK, USER, TASK, PROJECT
    AmountBillable      AS CONVERT(DECIMAL(19,2), CASE WHEN IsBillable = 1 THEN ROUND(BilledMinutes * RateApplied / 60.0, 2) ELSE 0 END) PERSISTED,
    TimeEntryStatusId   INT             NOT NULL,
    SubmittedAt         DATETIME2(0)    NULL,
    ApprovedAt          DATETIME2(0)    NULL,
    ApprovedBy          INT             NULL,
    RejectedAt          DATETIME2(0)    NULL,
    RejectedBy          INT             NULL,
    RejectedReason      NVARCHAR(500)   NULL,
    InvoiceEntryId      INT             NULL,      -- set when picked up by a draft invoice; locked once the invoice is issued
    DeletedAt           DATETIME2(0)    NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_TimeEntry_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_TimeEntry_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    TimesheetId         INT             NOT NULL,      -- the owner's week (crm.Timesheet); set by usp_TimeEntry_Save. Last so a publish appends it.
    CONSTRAINT UQ_TimeEntry_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_TimeEntry_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_TimeEntry_EntryMode CHECK (EntryMode IN ('HOUR', 'HALF_HOUR', 'QUARTER_HOUR', 'EXACT', 'START_END')),
    CONSTRAINT CK_TimeEntry_StartEnd CHECK (
        (EntryMode = 'START_END' AND StartTime IS NOT NULL)
        OR (EntryMode <> 'START_END' AND StartTime IS NULL AND EndTime IS NULL AND EnteredMinutes IS NOT NULL)),
    CONSTRAINT CK_TimeEntry_Minutes CHECK (
        (EnteredMinutes IS NULL OR EnteredMinutes BETWEEN 1 AND 1440)
        AND (BilledMinutes IS NULL OR BilledMinutes BETWEEN 1 AND 1440)),
    CONSTRAINT CK_TimeEntry_RateSource CHECK (RateSource IS NULL OR RateSource IN ('USER_TASK', 'USER', 'TASK', 'PROJECT')),
    CONSTRAINT CK_TimeEntry_Rate CHECK (RateApplied IS NULL OR RateApplied >= 0),
    -- task must belong to the project
    CONSTRAINT FK_TimeEntry_Task FOREIGN KEY (TenantId, ProjectId, TaskId) REFERENCES crm.ClientTask (TenantId, ProjectId, Id),
    CONSTRAINT FK_TimeEntry_Status FOREIGN KEY (TenantId, TimeEntryStatusId) REFERENCES lkp.TimeEntryStatus (TenantId, Id),
    CONSTRAINT FK_TimeEntry_Timesheet FOREIGN KEY (TenantId, TimesheetId) REFERENCES crm.Timesheet (TenantId, Id),
    CONSTRAINT FK_TimeEntry_InvoiceEntry FOREIGN KEY (TenantId, InvoiceEntryId) REFERENCES ar.InvoiceEntry (TenantId, Id),
    CONSTRAINT FK_TimeEntry_AppUser FOREIGN KEY (TenantId, AppUserId) REFERENCES sec.AppUser (TenantId, Id)
);
GO
CREATE NONCLUSTERED INDEX IX_TimeEntry_User_Date ON crm.TimeEntry (TenantId, AppUserId, WorkDate) WHERE DeletedAt IS NULL;
GO
-- unbilled / ready-to-invoice queries
CREATE NONCLUSTERED INDEX IX_TimeEntry_Project_Status ON crm.TimeEntry (TenantId, ProjectId, TimeEntryStatusId)
    INCLUDE (WorkDate, BilledMinutes, AmountBillable, IsBillable, InvoiceEntryId) WHERE DeletedAt IS NULL;
GO
-- one running timer per user
CREATE UNIQUE NONCLUSTERED INDEX UX_TimeEntry_RunningTimer ON crm.TimeEntry (TenantId, AppUserId)
    WHERE EntryMode = 'START_END' AND EndTime IS NULL AND DeletedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_TimeEntry_Timesheet ON crm.TimeEntry (TenantId, TimesheetId) INCLUDE (TimeEntryStatusId) WHERE DeletedAt IS NULL;
GO
CREATE NONCLUSTERED INDEX IX_TimeEntry_InvoiceEntry ON crm.TimeEntry (TenantId, InvoiceEntryId) WHERE InvoiceEntryId IS NOT NULL;
