# bywater-koha-release-notes-generator

This project automatically outputs release notes for a given branch of ByWater Solutions GitHub repository bywater-koha

The script is mean to be run using Docker via the command:
docker run --env KOHA_BRANCH=bywater-v17.05.06-01 kylemhall/bywater-koha-release-notes-generator

It could also be run locally by setting the environment variables KOHACLONE to point to your git clone of Koha, and KOHA_BRANCH to specify the branch of the repo for which to build release notes.
The local git repo used should have the remote bws-production set to point go bywatersolutions/bywater-koha on GitHub.

This project is quite ByWater specific but could be adapted for others to use to generate custom release notes for custom releases of Koha.
