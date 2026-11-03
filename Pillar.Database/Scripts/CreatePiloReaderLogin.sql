/*
One-time setup for Ask Pilo's read-only login (handoff 24). Not part of the build or the publish: run it by hand once per
server, in SSMS with Query > SQLCMD Mode on, after the dacpac with the PiloReader role is published.
Set the two variables first. Put the same password in the API's .env as the pillar_ai_reader connection; never commit it.
SQL Server must allow SQL logins (Server properties > Security > SQL Server and Windows Authentication mode).
On Azure SQL later, use a contained user instead: CREATE USER pillar_ai_reader WITH PASSWORD = '...'.
*/
:setvar DatabaseName "PillarDev"
:setvar PiloReaderPassword "change-me"

USE [master];
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'pillar_ai_reader')
    CREATE LOGIN pillar_ai_reader WITH PASSWORD = N'$(PiloReaderPassword)', CHECK_POLICY = ON, DEFAULT_DATABASE = [$(DatabaseName)];
GO
USE [$(DatabaseName)];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'pillar_ai_reader')
    CREATE USER pillar_ai_reader FOR LOGIN pillar_ai_reader;
ALTER ROLE PiloReader ADD MEMBER pillar_ai_reader;
GO
-- check: the login can read rpt and nothing else
EXECUTE AS USER = N'pillar_ai_reader';
SELECT HAS_PERMS_BY_NAME(N'rpt.Invoice', N'OBJECT', N'SELECT') AS CanReadRpt,      -- 1
       HAS_PERMS_BY_NAME(N'ar.Invoice', N'OBJECT', N'SELECT') AS CanReadTables;     -- 0
REVERT;
