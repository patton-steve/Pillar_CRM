"""Generates every lkp.Default<Name> / lkp.<Name> table pair and lkp.usp_SyncTenantLookups.

Usage: python3 GenerateLookups.py <path to Pillar.Database>

Add a lookup by adding a Lookup(...) to LOOKUPS. Order matters: a lookup whose extra
column points at another lookup must come after it (the sync proc copies in list order).
"""
import os
import sys
from dataclasses import dataclass, field


@dataclass
class Extra:
    """An extra column on both tables of a lookup pair."""
    name: str
    ddl: str                       # type + nullability, e.g. "INT NOT NULL"
    check: str = None              # CHECK body, applied to both tables
    ref_lookup: str = None         # FK to another lookup: master -> Default<ref>, tenant -> (TenantId, col) -> <ref>
    unique: bool = False           # unique per tenant (and on the master); sync skips defaults that would collide


@dataclass
class Lookup:
    name: str
    # None = plain list; "system" = every value must map to a SystemCode;
    # "locked" = SystemCode required and tenants cannot add values (rename/reorder only)
    mode: str = None
    extras: list = field(default_factory=list)


LOOKUPS = [
    Lookup("ClientType", "system"),
    Lookup("ClientStatus", "system"),
    Lookup("PaymentTerm", extras=[Extra("DueDays", "INT NOT NULL", check="DueDays >= 0")]),
    Lookup("Industry"),
    Lookup("AddressType"),
    Lookup("ContactRole"),
    Lookup("BillingType", "locked"),
    Lookup("ProjectStatus", "system"),
    Lookup("InvoiceFrequency", "system"),
    Lookup("TaskType"),
    Lookup("ProjectType", extras=[
        # task keys are <KeyPrefix>-<n>: 2-10 uppercase letters/digits, starting with a letter
        Extra("KeyPrefix", "VARCHAR(10) NOT NULL", unique=True,
              check="LEN(KeyPrefix) >= 2 AND KeyPrefix COLLATE Latin1_General_BIN NOT LIKE '%[^A-Z0-9]%' "
                    "AND LEFT(KeyPrefix, 1) COLLATE Latin1_General_BIN LIKE '[A-Z]'"),
        # pre-fills ClientProject.BillingTypeId
        Extra("DefaultBillingTypeId", "INT NULL", ref_lookup="BillingType"),
    ]),
    Lookup("TaskStatus", "system"),
    Lookup("TaskPriority"),
    Lookup("TimeEntryStatus", "locked"),
    Lookup("InvoiceStatus", "locked"),
    Lookup("InvoiceLineType", "locked"),
    Lookup("PaymentMethod"),
    # UnitName/UnitRate turn a category into quantity x rate (e.g. Mileage: mile x 0.67)
    Lookup("ExpenseCategory", extras=[
        Extra("UnitName", "NVARCHAR(20) NULL"),
        Extra("UnitRate", "DECIMAL(19,4) NULL", check="UnitRate IS NULL OR UnitRate >= 0"),
    ]),
    Lookup("BillStatus", "locked"),
    Lookup("TimesheetStatus", "locked"),
    Lookup("NoteType", "system"),
]

SESSION_USER = "CONVERT(INT, SESSION_CONTEXT(N'UserId'))"


def audit(t):
    return f"""    CreatedAt       DATETIME2(0)    NOT NULL CONSTRAINT DF_{t}_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CreatedBy       INT             NULL CONSTRAINT DF_{t}_CreatedBy DEFAULT ({SESSION_USER}),
    ModifiedAt      DATETIME2(0)    NULL,
    ModifiedBy      INT             NULL,
    RowVer          ROWVERSION      NOT NULL"""


def mode_checks(t, mode, master):
    out = ""
    if mode in ("system", "locked"):
        out += f"\n    CONSTRAINT CK_{t}_SystemCodeRequired CHECK (SystemCode IS NOT NULL),"
    if mode == "locked":
        body = "IsLocked = 1" if master else "IsCustom = 0 AND IsLocked = 1"
        out += f"\n    CONSTRAINT CK_{t}_NoCustom CHECK ({body}),  -- Pillar-defined list"
    return out


def extra_cols(lk):
    return "".join(f"    {e.name:<15} {e.ddl},\n" for e in lk.extras)


def extra_constraints(lk, t, master):
    out = ""
    for e in lk.extras:
        if e.check:
            out += f"\n    CONSTRAINT CK_{t}_{e.name} CHECK ({e.check}),"
        if e.unique:
            cols = e.name if master else f"TenantId, {e.name}"
            out += f"\n    CONSTRAINT UQ_{t}_{e.name} UNIQUE ({cols}),"
        if e.ref_lookup:
            if master:
                out += (f"\n    CONSTRAINT FK_{t}_{e.name} FOREIGN KEY ({e.name}) "
                        f"REFERENCES lkp.Default{e.ref_lookup} (Id),")
            else:
                out += (f"\n    CONSTRAINT FK_{t}_{e.name} FOREIGN KEY (TenantId, {e.name}) "
                        f"REFERENCES lkp.{e.ref_lookup} (TenantId, Id),")
    return out


def write_tables(root, lk):
    d = os.path.join(root, "lkp", "Tables")
    os.makedirs(d, exist_ok=True)
    name, dt = lk.name, "Default" + lk.name
    with open(os.path.join(d, dt + ".sql"), "w") as f:
        f.write(f"""-- Pillar master list for {name}. No TenantId; maintained by Pillar only.
-- New rows reach existing tenants through lkp.usp_SyncTenantLookups.
CREATE TABLE lkp.{dt}
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_{dt} PRIMARY KEY CLUSTERED,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_{dt}_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_{dt}_IsActive DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_{dt}_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_{dt}_IsDefault DEFAULT (0),   -- preselected in new-entry dropdowns
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), '{name}') PERSISTED NOT NULL,
{extra_cols(lk)}{audit(dt)},
    CONSTRAINT UQ_{dt}_Code UNIQUE (Code),{mode_checks(dt, lk.mode, True)}{extra_constraints(lk, dt, True)}
    CONSTRAINT FK_{dt}_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_{dt}_IsDefault ON lkp.{dt} (IsDefault) WHERE IsDefault = 1;
""")
    with open(os.path.join(d, name + ".sql"), "w") as f:
        f.write(f"""-- Tenant working list for {name}: Pillar defaults copied in at sign-up (DefaultId set)
-- plus the tenant's own values (IsCustom = 1, DefaultId NULL).
-- Core tables reference (TenantId, Id) so a row can only use its own tenant's values.
CREATE TABLE lkp.{name}
(
    Id              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_{name} PRIMARY KEY CLUSTERED,
    TenantId        INT             NOT NULL,
    Code            NVARCHAR(20)    NOT NULL,
    Name            NVARCHAR(100)   NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_{name}_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_{name}_IsActive DEFAULT (1),
    IsCustom        BIT             NOT NULL CONSTRAINT DF_{name}_IsCustom DEFAULT (1),
    IsLocked        BIT             NOT NULL CONSTRAINT DF_{name}_IsLocked DEFAULT (0),
    IsDefault       BIT             NOT NULL CONSTRAINT DF_{name}_IsDefault DEFAULT (0),  -- preselected in new-entry dropdowns
    DefaultId       INT             NULL,
    SystemCode      VARCHAR(30)     NULL,
    LookupName      AS CONVERT(VARCHAR(50), '{name}') PERSISTED NOT NULL,
{extra_cols(lk)}{audit(name)},
    CONSTRAINT UQ_{name}_Tenant_Id UNIQUE (TenantId, Id),{mode_checks(name, lk.mode, False)}{extra_constraints(lk, name, False)}
    CONSTRAINT UQ_{name}_Tenant_Code UNIQUE (TenantId, Code),
    CONSTRAINT FK_{name}_Tenant FOREIGN KEY (TenantId) REFERENCES admin.Tenant (Id),
    CONSTRAINT FK_{name}_Default FOREIGN KEY (DefaultId) REFERENCES lkp.Default{name} (Id),
    CONSTRAINT FK_{name}_SystemCode FOREIGN KEY (LookupName, SystemCode)
        REFERENCES lkp.SystemCode (LookupName, SystemCode),
    CONSTRAINT CK_{name}_CustomOrDefault CHECK ((IsCustom = 1 AND DefaultId IS NULL) OR (IsCustom = 0 AND DefaultId IS NOT NULL))
);
GO
-- One tenant row per default, so the sync proc never double-copies.
CREATE UNIQUE NONCLUSTERED INDEX UX_{name}_Tenant_Default
    ON lkp.{name} (TenantId, DefaultId) WHERE DefaultId IS NOT NULL;
GO
-- At most one default value per tenant.
CREATE UNIQUE NONCLUSTERED INDEX UX_{name}_Tenant_IsDefault
    ON lkp.{name} (TenantId) WHERE IsDefault = 1;
""")
        if lk.mode == "locked":
            # locked lists have exactly one row per behavior, so procs can look values up by SystemCode
            f.write(f"""GO
CREATE UNIQUE NONCLUSTERED INDEX UX_{name}_Tenant_SystemCode
    ON lkp.{name} (TenantId, SystemCode);
""")


def sync_block(lk):
    name = lk.name
    cols = "".join(", " + e.name for e in lk.extras)
    sel, joins, skips = "", "", ""
    for e in lk.extras:
        if e.ref_lookup:
            a = "r_" + e.name
            # map the master's FK to the same tenant's copy of that default
            joins += (f"\n    LEFT JOIN lkp.{e.ref_lookup} AS {a} "
                      f"ON {a}.TenantId = t.Id AND {a}.DefaultId = d.{e.name}")
            sel += f", {a}.Id"
        else:
            sel += f", d.{e.name}"
        if e.unique:
            skips += (f"\n      AND NOT EXISTS (SELECT 1 FROM lkp.{name} AS x "
                      f"WHERE x.TenantId = t.Id AND x.{e.name} = d.{e.name})")
    return f"""
    INSERT INTO lkp.{name} (TenantId, Code, Name, SortOrder, IsActive, IsCustom, IsLocked, IsDefault, DefaultId, SystemCode{cols})
    SELECT t.Id, d.Code, d.Name, d.SortOrder, d.IsActive, 0, d.IsLocked,
           -- keep a default the tenant already chose
           CASE WHEN EXISTS (SELECT 1 FROM lkp.{name} AS x WHERE x.TenantId = t.Id AND x.IsDefault = 1) THEN 0 ELSE d.IsDefault END,
           d.Id, d.SystemCode{sel}
    FROM admin.Tenant AS t
    CROSS JOIN lkp.Default{name} AS d{joins}
    WHERE (@TenantId IS NULL OR t.Id = @TenantId)
      AND NOT EXISTS (SELECT 1 FROM lkp.{name} AS x WHERE x.TenantId = t.Id AND x.DefaultId = d.Id)
      -- a tenant custom value may already hold the code; skip rather than fail
      AND NOT EXISTS (SELECT 1 FROM lkp.{name} AS x WHERE x.TenantId = t.Id AND x.Code = d.Code){skips};
"""


def write_sync_proc(root):
    sp = os.path.join(root, "lkp", "Stored Procedures")
    os.makedirs(sp, exist_ok=True)
    blocks = "".join(sync_block(lk) for lk in LOOKUPS)
    with open(os.path.join(sp, "usp_SyncTenantLookups.sql"), "w") as f:
        f.write(f"""-- Copies Pillar default lookup rows into tenant lists.
-- @TenantId = a tenant: called by sign-up to seed that tenant.
-- @TenantId = NULL: publishes newly added defaults to every tenant.
-- Only inserts missing rows; tenant renames, reorders and deactivations are never overwritten.
-- RLS: the caller must set SESSION_CONTEXT TenantId to the tenant, or IsPlatformAdmin = 1 for NULL.
-- Generated by tools/GenerateLookups.py; edit the generator, not this file.
CREATE PROCEDURE lkp.usp_SyncTenantLookups
    @TenantId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
{blocks}
    COMMIT;
END;
""")


if __name__ == "__main__":
    root = sys.argv[1]
    for lk in LOOKUPS:
        write_tables(root, lk)
    write_sync_proc(root)
    print([lk.name for lk in LOOKUPS])
