#!/usr/bin/perl

use Modern::Perl;

use Data::Dumper;
use REST::Client;
use JSON;
use Template;

my $debug = $ENV{DEBUG};

my $rest = REST::Client->new();

$debug && warn "KOHACLONE: " . $ENV{KOHACLONE};
chdir $ENV{KOHACLONE};

my $branch = $ENV{KOHA_BRANCH};

`git fetch --all >/dev/null 2>&1`;
`git checkout $branch >/dev/null 2>&1`;

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
            $prev_branch = $branches[ $i - 1 ];
        }
    }
}

# Handle case where this is the first special code fork, use corrosponding bywater-v* versions
if ( !$prev_branch && $edition ne 'bywater' ) {
    $prev_branch = "bywater-v$version";
}

$debug && warn "PREV BRANCH IS $prev_branch";

my @commits = `git log bws-production/$prev_branch..bws-production/$branch --pretty=oneline`;
$debug && warn "DIFF git log $prev_branch..$branch --pretty=oneline";
$_ =~ s/^\s+|\s+$//g for @commits;
@commits = map { substr( $_, 41 ) } @commits;
$debug && warn "COMMITS: " . Data::Dumper::Dumper( \@commits );

`git checkout $prev_branch >/dev/null 2>&1`;

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
    next unless $c;

    my $bws_pkg = 0;

    $debug && warn "CUSTOM FOR INSTANCE: $custom_for_instance";
    $debug && warn "RAW SUBJECT: $c";
    foreach my $m (@skip_messages) {
        if ( $c =~ /$m/ ) {
            $debug && warn "SKIPPING - Commit message contains '$m'";
            next COMMITS;
        }
    }

    if ( $c =~ /^BWS-PKG/ ) {
        $custom_for_instance = 0; # Done with instance custom code as soon as we hit a BWS-PKG commit
        $bws_pkg = 1;
        ( undef, $c ) = split( / - /, $c, 2 );    # Get rid of 'BWS-PKG - '
    } elsif ( $custom_for_instance ) {
        ( undef, $c ) = split( / - /, $c, 2 ); # Get rid of 'WASHOE - ' style prefixes;
    }

    $debug && warn "\nMUNGED SUBJECT: $c";

    my $commit = {
        title => $c,
        bws_pkg => $bws_pkg,
        custom_for_instance => $custom_for_instance,
    };

    my $escaped_c = $c;
    $escaped_c =~ s/"/\\"/g;    # Escape double quotes for searching
    $escaped_c =~ s/\[/\\\[/;
    $escaped_c =~ s/\]/\\\]/;
    my $command = qq{git log --pretty=oneline | grep "$escaped_c"};
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
foreach my $c (@commits_to_log_filtered) {
    if ( $c->{custom_for_instance} ) {
        push( @{ $commits->{'Custom For Instance'} }, $c );
    }
    elsif ( my $component = $c->{bugzilla}->{component} ) {
        push( @{ $commits->{$component} }, $c );
    }
    else {
        push( @{ $commits->{'Bywater Only'} }, $c );
    }
}

`git checkout $branch >/dev/null 2>&1`;

$debug && warn Data::Dumper::Dumper($commits);
$debug && warn "COUNT: " . scalar @commits_to_log_filtered;

my $template = q{
# Release Notes for [% branch %]

[%- FOREACH key IN commits.keys.sort %]
## [% key %]

  [%- FOREACH c IN commits.$key %]
    [%- IF c.bugzilla.id %]
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

if ( $ENV{UPLOAD} ) {
    my $token = $ENV{GITHUB_TOKEN};
    `git clone https://$token\@github.com/bywatersolutions/bywater-koha-release-notes.git`;
    chdir './bywater-koha-release-notes';
    `git config --global user.email 'kyle\@bywatetsolutions.com'`;
    `git config --global user.name 'Kyle M Hall'`;
    my $filename = "$branch.md";
    open( my $fh, '>', $filename );
    print $fh $output . "\n";
    close $fh;
    `cat $prev_branch.md >> $filename`;
    `git add *`;
    `git commit -a -m 'Added $filename'`;
    `git push origin HEAD:master`;
    chdir '..';
    `rm -rf bywater-koha-release-notes`;
    
    qx{curl -s --user 'api:$ENV{MAILGUN_TOKEN}' \\
        https://api.mailgun.net/v3/sandbox7442ed4ef2884700b429df9b976f6398.mailgun.org/messages \\
        -F from='Kyle M Hall <kyle\@bywatersolutions.com>' \\
        -F to=pipeline\@bywatersolutions.com \\
        -F subject='New Release Notes: $filename' \\
        -F text='New ByWater Release notes added: https://github.com/bywatersolutions/bywater-koha-release-notes/blob/master/$filename'
    };
}
else {
    say $output;
}
