-- Signed-in password change (the API has already checked the current password). Signs out the user's other sessions:
-- pass the current @KeepFamilyId to stay signed in here.
CREATE PROCEDURE sec.usp_Auth_SetPassword
    @PasswordHash   VARCHAR(255),
    @KeepFamilyId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId INT = CAST(SESSION_CONTEXT(N'UserId') AS INT), @Now DATETIME2(0) = SYSUTCDATETIME();
    IF @UserId IS NULL THROW 50952, N'No user in session.', 1;

    BEGIN TRAN;
    UPDATE sec.UserCredential
    SET PasswordHash = @PasswordHash, PasswordChangedAt = @Now, MustChangePassword = 0, ModifiedAt = @Now
    WHERE AppUserId = @UserId;
    UPDATE sec.RefreshToken SET RevokedAt = @Now, RevokedReason = 'PASSWORD_RESET'
    WHERE AppUserId = @UserId AND RevokedAt IS NULL AND (@KeepFamilyId IS NULL OR FamilyId <> @KeepFamilyId);
    COMMIT;
END;
