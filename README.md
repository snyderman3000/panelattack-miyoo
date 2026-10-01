# builds branch

Release zips built from `main` (see docs/BUILDING.md there). Pushing this
branch runs `publish.yml`, which publishes a GitHub release `vX.Y.Z` for every
`PanelAttack-miyoo-vX.Y.Z.zip` here that isn't released yet, using
`notes-vX.Y.Z.md` as the description, and attaches everything in `sources/`
(source code that bundled LGPL libraries require) to every release. Mixtape picks up new releases from there.
