-- Banners Pillar shows to every signed-in person: what's new (INFO) or planned downtime (MAINTENANCE). Global (no TenantId),
-- edited in the back office with admin.usp_Announcement_Save. Showing while IsActive = 1 and now is between StartsAt and EndsAt
-- (NULL = no end). A person hides one with sec.usp_Announcement_Dismiss.
CREATE TABLE admin.Announcement
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Announcement PRIMARY KEY CLUSTERED,
    Title           NVARCHAR(200)   NOT NULL,
    Body            NVARCHAR(2000)  NULL,
    Severity        VARCHAR(12)     NOT NULL CONSTRAINT DF_Announcement_Severity DEFAULT ('INFO'),
    LinkUrl         NVARCHAR(400)   NULL,
    StartsAt        DATETIME2(0)    NOT NULL,
    EndsAt          DATETIME2(0)    NULL,
    IsActive        BIT             NOT NULL CONSTRAINT DF_Announcement_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_Announcement_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_Announcement_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    CONSTRAINT CK_Announcement_Severity CHECK (Severity = 'INFO' OR Severity = 'MAINTENANCE'),
    CONSTRAINT CK_Announcement_Window CHECK (EndsAt IS NULL OR EndsAt > StartsAt)
);
