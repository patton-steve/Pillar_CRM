-- A person in one tenant. Logins are 1:1 with a tenant (Steve 2026-10-20): someone who works for two tenants has two users,
-- each with its own email. CanLogin = 0 is a billable person without a login (e.g. a subcontractor whose time the owner enters);
-- inviting them later turns on CanLogin on the same row, so their history stays attached.
-- Status: INVITED (login pending), ACTIVE, DISABLED. Passwords, MFA and lockout live in sec.UserCredential.
-- Avatar (Steve 2026-10-21): AvatarKind INITIALS (default), PHOTO (sec.UserAvatar) or PILO (a Pilo emote from admin.PiloEmote
-- in the person's own primary/secondary colors). Email is changed only by an admin (sec.usp_User_ChangeEmail).
-- EmailSignatureHtml is sanitized HTML, the {SenderSignature} merge field in email templates.
-- sec.trg_AppUser_Rules enforces Tenant.MaxUsers, the last active owner, platform-admin changes, and keeps the credential in step.
CREATE TABLE sec.AppUser
(
    Id                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppUser PRIMARY KEY CLUSTERED,
    PublicId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AppUser_PublicId DEFAULT (NEWSEQUENTIALID()),
    TenantId            INT             NOT NULL,
    Email               NVARCHAR(254)   NULL,      -- required to log in; optional for no-login people
    EmailNormalized     AS CONVERT(NVARCHAR(254), LOWER(LTRIM(RTRIM(Email)))) PERSISTED,
    FirstName           NVARCHAR(100)   NOT NULL,
    LastName            NVARCHAR(100)   NULL,
    DisplayName         AS CONCAT_WS(N' ', FirstName, LastName),
    Title               NVARCHAR(100)   NULL,
    Phone               NVARCHAR(30)    NULL,
    UserType            VARCHAR(12)     NOT NULL CONSTRAINT DF_AppUser_UserType DEFAULT ('EMPLOYEE'),   -- EMPLOYEE, CONTRACTOR
    VendorId            INT             NULL,      -- contractor paid through AP
    RoleId              INT             NOT NULL,
    CanLogin            BIT             NOT NULL CONSTRAINT DF_AppUser_CanLogin DEFAULT (1),
    Status              VARCHAR(10)     NOT NULL CONSTRAINT DF_AppUser_Status DEFAULT ('ACTIVE'),
    DefaultBillRate     DECIMAL(19,4)   NULL,      -- suggested for new project rates
    CostRate            DECIMAL(19,4)   NULL,      -- internal cost per hour, for margin reporting; never printed
    TimeZoneId          NVARCHAR(64)    NULL,      -- NULL = tenant time zone
    IsPlatformAdmin     BIT             NOT NULL CONSTRAINT DF_AppUser_IsPlatformAdmin DEFAULT (0),  -- Pillar staff only
    DisabledAt          DATETIME2(0)    NULL,
    CreatedAt           DATETIME2(0)    NOT NULL CONSTRAINT DF_AppUser_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy           INT             NULL CONSTRAINT DF_AppUser_CreatedBy DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'UserId'))),
    ModifiedAt          DATETIME2(0)    NULL,
    ModifiedBy          INT             NULL,
    RowVer              ROWVERSION      NOT NULL,
    AvatarKind          VARCHAR(10)     NOT NULL CONSTRAINT DF_AppUser_AvatarKind DEFAULT ('INITIALS'),   -- handoff 21: appended
    AvatarPiloEmote     VARCHAR(20)     NULL,
    AvatarPrimaryColor  CHAR(7)         NULL,      -- #RRGGBB
    AvatarSecondaryColor CHAR(7)        NULL,
    EmailSignatureHtml  NVARCHAR(MAX)   NULL,
    CONSTRAINT UQ_AppUser_PublicId UNIQUE (PublicId),
    CONSTRAINT UQ_AppUser_Tenant_Id UNIQUE (TenantId, Id),
    CONSTRAINT CK_AppUser_UserType CHECK (UserType IN ('EMPLOYEE', 'CONTRACTOR')),
    CONSTRAINT CK_AppUser_Status CHECK (Status IN ('INVITED', 'ACTIVE', 'DISABLED')),
    CONSTRAINT CK_AppUser_LoginEmail CHECK (CanLogin = 0 OR Email IS NOT NULL),
    CONSTRAINT CK_AppUser_Invited CHECK (Status <> 'INVITED' OR CanLogin = 1),
    CONSTRAINT CK_AppUser_AvatarKind CHECK (AvatarKind = 'INITIALS' OR AvatarKind = 'PHOTO' OR (AvatarKind = 'PILO' AND AvatarPiloEmote IS NOT NULL)),
    CONSTRAINT CK_AppUser_AvatarColors CHECK ((AvatarPrimaryColor IS NULL OR AvatarPrimaryColor LIKE '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]')
        AND (AvatarSecondaryColor IS NULL OR AvatarSecondaryColor LIKE '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]')),
    CONSTRAINT FK_AppUser_PiloEmote FOREIGN KEY (AvatarPiloEmote) REFERENCES admin.PiloEmote (Code),
    CONSTRAINT FK_AppUser_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_AppUser_Role FOREIGN KEY (TenantId, RoleId) REFERENCES sec.Role (TenantId, Id),
    CONSTRAINT FK_AppUser_Vendor FOREIGN KEY (TenantId, VendorId) REFERENCES ap.Vendor (TenantId, Id)
);
GO
-- a login email belongs to exactly one user in all of Pillar
CREATE UNIQUE NONCLUSTERED INDEX UX_AppUser_LoginEmail ON sec.AppUser (EmailNormalized) WHERE CanLogin = 1;
GO
CREATE NONCLUSTERED INDEX IX_AppUser_Tenant_Status ON sec.AppUser (TenantId, Status) INCLUDE (CanLogin, RoleId);
