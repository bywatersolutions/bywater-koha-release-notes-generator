#!/usr/bin/perl

use Modern::Perl;

use File::Slurp;
use Data::Dumper;
use REST::Client;
use JSON;
use Template;

my $debug = $ENV{DEBUG};

my $rest = REST::Client->new();

my $dir = '.';

$debug && warn "KOHACLONE: " . $ENV{KOHACLONE};
chdir $ENV{KOHACLONE};

my $branch = read_file( $ENV{KOHACLONE} . "/misc/bwsbranch");
chomp $branch;

$debug && warn "BRANCH IS $branch";

my ( $edition, $version, $mark ) = split( /-/, $branch );
$version = substr( $version, 1 );

$debug && warn "EDITION: $edition";
$debug && warn "VERSION: $version";
$debug && warn "MARK: $mark";

my ( $major, $minor, $patch ) = split( /\./, $version );

$debug && warn "MAJOR: $major";
$debug && warn "MINOR: $minor";
$debug && warn "PATCH: $patch";

my @branches = `git branch -r --list bws-production/$edition-v*`;
$_ =~ s/^\s+|\s+$//g for @branches;
@branches = map { @{ [ split( /\//, $_ ) ] }[1] } @branches;
my $prev_branch;
for ( my $i = 0 ; $i < scalar @branches ; $i++ ) {
    if ( $branches[$i] eq $branch ) {
        if ( $i > 0 ) {
            $debug && warn "PREV BRANCH IS " . $branches[ $i - 1 ];
            $prev_branch = $branches[ $i - 1 ];
        }
        else {
            # FIXME: Handle case where this is the first 
            # special code fork, search bywater-v* versions?
        }
    }
}

my @commits = `git log $prev_branch..$branch --pretty=oneline`;
$debug && warn "DIFF git log $prev_branch..$branch --pretty=oneline";
$_ =~ s/^\s+|\s+$//g for @commits;
@commits = map { substr( $_, 41 ) } @commits;

`git checkout $prev_branch`;

my @skip_messages = (
    "bwsbranch",
    "Travis CI",
    "Merge remote-tracking branch",
    "release notes",
    "Increment version for",
    "Translation updates for"
);

my $custom_for_instance = $edition eq 'bywater' ? 0 : 1;
my @commits_to_log;
COMMITS: foreach my $c (@commits) {
    ( undef, $c ) = split( / - /, $c, 2 )
      if $custom_for_instance;    # Get rid of 'WASHOE - ' style prefixes;
    $debug && warn "\nLOOKING AT $c";

    my $commit = { title => $c };

    foreach my $m (@skip_messages) {
        if ( $c =~ /$m/ ) {
            $debug && warn "SKIPPING - Commit message contains '$m'";
            next COMMITS;
        }
    }

    if ( $c =~ /^BWS-PKG/ ) {
        $debug && warn "STOPPING - End of custom of instance commits" && last
          if $custom_for_instance
          ; # If we are on a custom site branch, we only need to add the custom stuff. The notes on the 'bywater' branch have already added the rest.

        $commit->{title} = $c;    # Get rid of BWS-PKG in title

        $commit->{bws_pkg} = 1;
        ( undef, $c ) = split( / - /, $c, 2 );    # Get rid of 'BWS-PKG - '
    }

    my $escaped_c = $c;
    $escaped_c =~ s/"/\\"/g;    # Escape double quotes for searching
    my $command = q{git log --pretty=oneline | grep "\Q} . $escaped_c . q{\E"};
    my ($already_found) = `$command`;
    if ($already_found) {

        # This commit was in the previous version
        # but with a different commit id ( from being cherry-picked )
        $debug && warn "SKIPPING - Found in previous branch";
        next COMMITS;
    }

    $c =~ m/([B|b]ug|BZ)?\s?(?<![a-z]|\.)(\d{3,5})[\s|:|,]/g;
    $commit->{bug_number} = $2;

    $debug && warn "KEEPING $c";
    push( @commits_to_log, $commit );
}

my %seen;
my @commits_to_log_filtered =
  grep { !$_->{bug_number} || !$seen{ $_->{bug_number} }++ } @commits_to_log;

foreach my $c (@commits_to_log_filtered) {
    if ( $c->{bug_number} ) {
        $rest->GET( 'https://bugs.koha-community.org/bugzilla3/rest/bug/'
              . $c->{bug_number} );
        my $data = from_json( $rest->responseContent() );
        $c->{bugzilla} = $data->{bugs}->[0];
    }
}

# Group by component
my $commits = {};
foreach my $c ( @commits_to_log_filtered ) {
    if ( my $component = $c->{bugzilla}->{component} ) {
        push( @{ $commits->{ $component } }, $c );
    } else {
        push( @{ $commits->{'Bywater Only'} }, $c );
    }
}

`git checkout $branch`;

$debug && warn Data::Dumper::Dumper( $commits );
$debug && warn  "COUNT: " . scalar @commits_to_log_filtered;

my $template = q{
# Release Notes for [% branch %]

[%- FOREACH key IN commits.keys %]
## [% key %]

  [%- FOREACH c IN commits.$key %]
    [%- IF c.bug_number %]
- [[[% c.bugzilla.id %]]](http://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=[% c.bugzilla.id %]) [%- c.bugzilla.summary %]
    [%- ELSE %]
- NOT IN BUGZILLA - [%- c.title %]
    [%- END %]
  [%- END %]

[%- END %]
};

my $tt = Template->new();
my $output;
$tt->process(
    \$template,
    {
        branch  => $branch,
        edition => $edition,
        version => $version,
        commits => $commits,
    },
    \$output
);
say $output;
