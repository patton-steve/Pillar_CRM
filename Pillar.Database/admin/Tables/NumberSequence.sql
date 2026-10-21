-- Per-tenant counters for human-readable numbers: task keys ('TASK:PM' -> PM-118), invoice numbers ('INVOICE').
-- Tenants can set the format and the next value (e.g. start invoices at 1001 when migrating).
-- Formatted number = Prefix + [yyyy + '-' when IncludeYear] + number left-padded with zeros to PadLength.
--   e.g. Prefix 'INV-', IncludeYear 1, PadLength 5 -> INV-2026-00042
-- ResetPolicy YEARLY restarts at 1 in the first allocation of a new year (pair it with IncludeYear).
-- Allocated by admin.usp_NextNumber inside the caller's transaction, so a rollback returns the number (no gaps).
CREATE TABLE admin.NumberSequence
(
    TenantId        INT             NOT NULL,
    SequenceKey     VARCHAR(30)     NOT NULL,
    Prefix          NVARCHAR(20)    NULL,
    IncludeYear     BIT             NOT NULL CONSTRAINT DF_NumberSequence_IncludeYear DEFAULT (0),
    PadLength       TINYINT         NOT NULL CONSTRAINT DF_NumberSequence_PadLength DEFAULT (0),
    ResetPolicy     VARCHAR(10)     NOT NULL CONSTRAINT DF_NumberSequence_ResetPolicy DEFAULT ('NONE'),
    CurrentYear     SMALLINT        NULL,      -- year of the last allocation, for YEARLY reset
    NextValue       INT             NOT NULL CONSTRAINT DF_NumberSequence_NextValue DEFAULT (1),
    ModifiedAt      DATETIME2(0)    NULL,
    CONSTRAINT PK_NumberSequence PRIMARY KEY CLUSTERED (TenantId, SequenceKey),
    CONSTRAINT CK_NumberSequence_NextValue CHECK (NextValue >= 1),
    CONSTRAINT CK_NumberSequence_PadLength CHECK (PadLength <= 10),
    CONSTRAINT CK_NumberSequence_ResetPolicy CHECK (ResetPolicy IN ('NONE', 'YEARLY')),
    CONSTRAINT FK_NumberSequence_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id)
);
