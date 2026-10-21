-- Consumes one MFA recovery code during sign-in (no session context yet). @CodeHash is the API's hash of the code the user typed.
-- Removes that hash from RecoveryCodeHashes and returns Used = 1, or Used = 0 when it isn't there (wrong or already used code).
-- MfaSecretEncrypted and MfaEnabledAt are left as they are. Writes MFA_RECOVERY_USED (with the codes left) to sec.LoginAudit;
-- a rejected code goes through sec.usp_Auth_RecordLogin as MFA_FAIL, so it counts toward lockout. The API should not log it again.
CREATE PROCEDURE sec.usp_Auth_UseRecoveryCode
    @AppUserId      INT,
    @CodeHash       VARCHAR(64),
    @IpAddress      VARCHAR(45) = NULL,
    @UserAgent      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @TenantId INT, @Email NVARCHAR(254), @Codes NVARCHAR(MAX),
            @Used BIT = 0, @Remaining INT = 0;

    BEGIN TRAN;

    SELECT @TenantId = TenantId, @Email = LoginEmail, @Codes = RecoveryCodeHashes
    FROM sec.UserCredential WITH (UPDLOCK, HOLDLOCK)
    WHERE AppUserId = @AppUserId AND IsEnabled = 1 AND MfaEnabledAt IS NOT NULL;

    IF @Codes IS NOT NULL AND EXISTS (SELECT 1 FROM OPENJSON(@Codes) WHERE [type] = 1 AND [value] = @CodeHash)
    BEGIN
        SET @Used = 1;

        SELECT @Remaining = COUNT(*),
               @Codes = N'[' + ISNULL(STRING_AGG(CONVERT(NVARCHAR(MAX), N'"' + STRING_ESCAPE([value], 'json') + N'"'), N',')
                                     WITHIN GROUP (ORDER BY CONVERT(INT, [key])), N'') + N']'
        FROM OPENJSON(@Codes)
        WHERE [type] = 1 AND [value] <> @CodeHash;

        UPDATE sec.UserCredential
        SET RecoveryCodeHashes = @Codes, ModifiedAt = @Now
        WHERE AppUserId = @AppUserId;
    END;

    IF @Used = 1
        INSERT INTO sec.LoginAudit (EventType, Email, TenantId, AppUserId, Detail, IpAddress, UserAgent)
        VALUES ('MFA_RECOVERY_USED', @Email, @TenantId, @AppUserId, CONCAT(N'Recovery code used; ', @Remaining, N' left'),
                @IpAddress, @UserAgent);

    COMMIT;

    -- A rejected code counts toward the 5-attempt lockout like any other MFA failure (one MFA_FAIL row, written there).
    IF @Used = 0
        EXEC sec.usp_Auth_RecordLogin @EventType = 'MFA_FAIL', @AppUserId = @AppUserId, @Detail = N'Recovery code not accepted',
             @IpAddress = @IpAddress, @UserAgent = @UserAgent;

    SELECT @Used AS Used, @Remaining AS CodesRemaining;
END;
