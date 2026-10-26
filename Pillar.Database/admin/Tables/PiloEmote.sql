-- Pilo emotes people can pick as their avatar (sec.AppUser.AvatarPiloEmote), drawn by the UI in the person's own colors.
-- Pillar-owned, seeded by the post-deploy script; the picker lists the active rows in SortOrder.
CREATE TABLE admin.PiloEmote
(
    Code            VARCHAR(20)     NOT NULL CONSTRAINT PK_PiloEmote PRIMARY KEY CLUSTERED,
    Name            NVARCHAR(50)    NOT NULL,
    SortOrder       INT             NOT NULL CONSTRAINT DF_PiloEmote_SortOrder DEFAULT (0),
    IsActive        BIT             NOT NULL CONSTRAINT DF_PiloEmote_IsActive DEFAULT (1)
);
