-- Ask Pilo's read-only database role (handoff 24). The pillar_ai_reader login is its only member (Scripts\CreatePiloReaderLogin.sql,
-- run once by hand, because logins and passwords don't belong in the dacpac). The API runs the SQL Pilo writes on that
-- connection only, after sec.usp_PiloReader_SetContext has pinned the session to one tenant and person.
-- It can read the rpt views and their descriptions, and run those two procs; nothing else. The views reach the base tables
-- through ownership chaining (every schema is owned by dbo), and RLS still limits every row to the session tenant.
CREATE ROLE PiloReader AUTHORIZATION dbo;
GO
GRANT SELECT ON SCHEMA::rpt TO PiloReader;
GO
GRANT VIEW DEFINITION ON SCHEMA::rpt TO PiloReader;
GO
GRANT EXECUTE ON OBJECT::sec.usp_PiloReader_SetContext TO PiloReader;
GO
GRANT EXECUTE ON OBJECT::admin.usp_PiloCatalog TO PiloReader;
